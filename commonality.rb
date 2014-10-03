require 'csv'
require 'rubygems'
require 'mechanize'

# The Wesleyan Student directory link to scrape from
$url = "https://iasext.wesleyan.edu/directory_public/f?p=100:3:1657553273707010::::::"

# Global to store names and counts in
$name_counts = Hash.new(0)

# Array of the letters in the alphabet to recursively search through.
$alphabet = ("a".."z").to_a

## function add_counts()

=begin

Because the database only returns a maximum of 30 results, we can't
search just by first name, as there are some first names with more than
30 instances. However, running a search on the most common last names
showed that, even for the most common last name in America, Smith,
there were only 15 instances. Checking the next few most popular surnames
proved that none of them returned more than 15 studnets, so it seemed
safe to assume that no search on any particualr student's last name
would return more than 30 results. From here, it is relatively simple
to recursively build up strings that get longer until they return less
than 30 results when searched as a last name. For example, going through
the alphabet the first time, we reach the letter 'S'. Searching this 
in the database will probably return more than 30 results; if it does,
we call the algorith again, adding each letter in turn from the alphabet
again to 'S'. For each two-character string we create, we will
either see no results, less than 30 results, or more than 30 results.
If we see none, we can return from the call and move on to the next 
letter to add to 'S'. If we see less than 30, we can add each first name (which is 
returned with the last names) to our list (or add one to its instance
count if we've seen it before). We can then return and move on to the 
next character, because we've accounted for every student whose last name
begins with that unique character sequence. If more than 30 are again returned,
though, we have to narrow the search further. We call the routine on our
current string, again adding each letter of the alphabet in turn, until
we get less than 30 results. This will happen eventually,
as even the most common unique 'strings' (full last names) only return ~15
results.

=end

def add_counts(name_frag, options={})
  defaults = { "year" => -1 }
  options = defaults.merge(options)
  # Use Mechanize to grab the page to scrape
  mech = Mechanize.new
  mech.get($url)

  # Get the search form, and fill the Student Search field
  # with the supplied name fragment.

  form = mech.page.forms[0]
  form["p_t04"] = name_frag

  # Submit the form (last name search is the default; we don't need to set it)
  form.submit()

  # If the 'pagination' element isn't present, we got no results. Return
  # without doing anything further.
  if mech.page.parser.css("td[class='pagination']")[2] == nil
    return 0
  end

  # Check for the line '30 of more than 30' to indicate overflow
  overflow = mech.page.parser.css("td[class='pagination']")[2].text

  if overflow.include? "more"
    # If overflow, go deeper
    $alphabet.each do |c|
      add_counts(name_frag + c, options)
    end
  else
    # Otherwise, extract the first names from the returned page...
    result_names = mech.page.parser.css("span[class='name']").map{|n| n.text.split(", ")[1]}

    # ...and add one to each names's count in the global array
    # for each time it appears
    result_names.each do |n|
      $name_counts[n] += 1
    end
  end

  return 0
end

greeting = "\n\n** commonality.rb by Grant Addis **\n\n" +
  "Please select a mode:\n" +
  "[1]: Basic operation\n" +
  "[2]: Force use of external data\n" +
  "[3]: Display list with common spellings merged\n"  +
  "[4]: Display list for each gender\n" +
  "[5]: Display list for a specific class\n" +
  "[6]: The Works (Force data refresh and display spelling-adjusted lists for both genders " +
  "in a specific class)\n\n"

puts greeting

mode = gets.strip.to_i

puts "Running under mode #{mode}"

year = -1

if mode == 5 || mode == 6
  puts "Please enter a class year:"
  year = gets.strip.to_i
  if year >= 2015 && year <= 2018
    puts "Filtering by Class of #{year}"
  else
    puts "Invald input. Exiting..."
    exit
  end
end

# Check for local data to avoid downloading, if possible and if user
# did not force data refresh
case mode
when 1,3,4,5
  if File.exist? "names.csv"
    # Read the local data, if it exists
    CSV.foreach("names.csv") do |name, count|
      $name_counts[name] += count.to_i
    end
  else
    # Otherwise, start the recursion process
    puts "No local data present.\n" +
      "Fetching data from live website..."
    $alphabet.each do |c|
      add_counts(c)
      puts "Done processing #{c}..."
    end
  end
when 2,6
  puts "Fetching data from live website..."

  $alphabet.each do |c|
    add_counts(c)
    puts "Done processing #{c}..."
  end
else
  puts "Invalid input. Exiting."
  exit
end

# There is a bug either in the database or in Mechanize; 
# a student named Matthew Metros comes back with the first name
# "Matthew " (with a trailing space).

$name_counts["Matthew"] += 1
$name_counts.delete("Matthew ")

# If the user requests that names be sorted into categories of similar
# spelling, merge different names under a shortened header
case mode
when 3
  name_categories = Hash.new(0)

  alternate_spellings = {
    "Sara" => "Sarah",
    "Matthew" => "Matt",
    "Emilie" => "Emily",
    "Michel" => "Michael",
    "Becky" => "Rebecca",
    "Rachael" => "Rachel",
    "William" => "Will",
    "Zachary" => "Zach",
    "Zachariah" => "Zach",
    "Zack" => "Zach",
    
    # "Alex" is a tricky case, as it can be a full
    # male first name, or shortened version of 
    # either the female Alexandra or male Alexander.
    # To be safe, count them all and simply report
    # the total under "Alex".
    "Alexander" => "Alex",
    "Alexandra" => "Alex",

    # The same problem exists for "Sam"
    # (Samantha and Samuel)
    "Samuel" => "Sam",
    "Samantha" => "Sam",

    # As well as "Gabe" (Gabriel and
    # Gabrielle)
    "Gabriel" => "Gabe",
    "Gabrielle" => "Gabe",

    "Jonathan" => "John",
    "Jon" => "John",
    "Christopher" => "Chris",
    "Benjamin" => "Ben",
    "Katherine" => "Catherine",
    "Nicholas" => "Nick",
    "Joshua" => "Josh",
    "Maxwell" => "Max"
  }
  
  $name_counts.each{|name, count|
    if alternate_spellings.has_key? name
      name_categories[alternate_spellings[name]] += count.to_i
    else
      name_categories[name] += count.to_i
    end
  }

  $sorted_counts = name_categories.to_a.sort_by{|n| n[1]}.reverse

  # Write the data to disk
  CSV.open("names_categorized.csv", "wb") do |csv|
    $sorted_counts.each do |pair|
      csv << pair
    end
  end
else
  # Sort by names by frequency, descending
  $sorted_counts = $name_counts.to_a.sort_by{|n| n[1]}.reverse

  # Write the data to disk, if it wasn't there already
  if !File.exist? "names.csv"
    CSV.open("names.csv", "wb") do |csv|
      $sorted_counts.each do |pair|
        csv << pair
      end
    end
  end
end

case mode
when 1,2
  puts "\nTop 25 first names at Wes:\n"
when 3
  puts "\nTop 25 first name categories at Wes\n"
end

(0..24).each do |i|
  puts "#{i+1}: #{$sorted_counts[i][0]} (#{$sorted_counts[i][1]})"
end

puts "\nThis information is also stored in ./names.csv."
