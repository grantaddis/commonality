require 'csv'
require 'rubygems'
require 'mechanize'

# The Wesleyan Student directory link to scrape from
$url = "https://iasext.wesleyan.edu/directory_public/f?p=100:3:1657553273707010::::::"

# Global to store our accumulated data
$names_by_year = { 
  2015 => Hash.new(0), 
  2016 => Hash.new(0), 
  2017 => Hash.new(0),
  2018 => Hash.new(0)
}

# Some students are listed in the directory, but are graduate students
# or are part of some other non-undergrad program. These will be displayed
# when generic data is requested, but not when a specific undergrad class
# is requested
$non_undergrad_names = Hash.new(0)  

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

def add_counts(name_frag)
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
    ('a'..'z').each do |c|
      add_counts(name_frag + c)
    end
  else
    # Otherwise, extract the first names from the returned page
    result_names = mech.page.parser.css("span[class='name']").map{|n| n.text.split(", ")[1]}

    # Getting class years requires filtering through a class of spans that is
    # used for both class year and phone number. We only want every other entry
    result_years = mech.page.parser.css("span[class='ptext']").reject.with_index{|e, i|
      i % 2 == 0}

    # Add one to each names's count in the global array
    # for each time it appears, filtering by class year
    result_names.each_with_index do |n, i|
      if (result_years[i].text.to_i >= 2015) && (result_years[i].text.to_i <= 2018)
        $names_by_year[result_years[i].text.to_i][n] += 1
      else
        $non_undergrad_names[n] += 1
      end
    end
  end

  return 0
end

# Usage notes

greeting = "\n\n** commonality.rb by Grant Addis **\n\n" +
  "Please select a mode:\n" +
  "[1]: Basic operation\n" +
  "[2]: Force reload of external data\n" +
  "[3]: Display list with common spellings merged\n"  +
  "[4]: Display list for each gender\n" +
  "[5]: Display list for a specific class\n" +
  "[6]: The Works (Force data refresh and display spelling-adjusted lists for both genders " +
  "in a specific class)\n\n"

puts greeting

# Get parameters form user and perform some basic sanitation

mode = gets.strip.to_i

puts "Running under mode #{mode}"

if mode == 5 || mode == 6
  puts "Please enter a class year:"
  $year = gets.strip.to_i
  if ($year >= 2015) && ($year <= 2018)
    puts "Filtering by Class of #{$year}"
  else
    puts "Invald input. Exiting from range check..."
    exit
  end
end

# Check for local data to avoid downloading, if possible and if user
# did not force data refresh
case mode
when 1,3,4,5
  if File.exist? ".raw_names_2015.csv" # Assume one .raw file means all are there
    (2015..2018).each do |y|
      CSV.foreach(".raw_names_" + y.to_s + ".csv") do |name, count|
        $names_by_year[y][name] += count.to_i
      end
    end
    CSV.foreach(".raw_names_other.csv") do |name, count|
      $non_undergrad_names[name] += count.to_i
    end
  else
    # Otherwise, start the recursion process
    puts "No local data present.\n" +
      "Fetching data from live website..."
    ('a'..'z').each do |c|
      add_counts(c)
      puts "Done processing #{c}..."
    end
  end
when 2,6
  # If the user requests a data refresh, then start the recursion process
  puts "Fetching data from live website..."

  ('a'..'z').each do |c|
    add_counts(c)
    puts "Done processing #{c}..."
  end
else
  puts "Invalid input. Exiting."
  exit
end

# Mappings of common spellings that cover the top 25 lists we're dealing with
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


# YIKES this might be dangerous political territory...
# Stores names and best guess as to their corresponding gender.
# For names that are used by both genders, the percentage of 
# boys born in the 1990's with that name out of the total number
# of children born with that name in the 90's [Soure:
# babynamewizard.com] is listed. Again, this does not cover every possible
# name, but just the ones we run into in our top 25 lists.
gender_categories = { 
  "Daniel" => "m", "Sarah" => "f", "Matthew" => "m", "William" => "m", "Emily" => "f", "Michael" => "m", "Rebecca" => "f", "Rachel" => "f", "Zachary" => "m", "Alexander" => "m", "Emma" => "f", "Samuel" => "m", "Hannah" => "f", "John" => "m", "James" => "m", "Christopher" => "m", "David" => "m", "Benjamin" => "m", "Jacob" => "m", "Elizabeth" => "f", "Andrew" => "m", "Jessica" => "f", "Anna" => "f", "Katherine" => "f", "Gabriel" => "m", "Joseph" => "m", "Ryan" => "m", "Julia" => "f", "Nicholas" => "m", "Jordan" => ["b", 0.705], "Joshua" => "m", "Alexandra" => "f", "Olivia" => "f", "Thomas" => "m", "Robert" => "m", "Nicole" => "f", "Samantha" => "f", "Abigail" => "f", "Adam" => "m", "Ethan" => "m", "Caroline" => "f", "Claire" => "f", "Eric" => "m", "Aaron" => "m", "Jonathan" => "m", "Sara" => "f", "Maxwell" => "m", "Jack" => "m", "Noah" => "m", "Lauren" => "f", "Dylan" => "m", "Molly" => "f", "Gregory" => "m", "Kevin" => "m", "Charles" => "m", "Peter" => "m", "Maya" => "f", "Taylor" => ["b", 0.263], "Grace" => "f", "Laura" => "f", "Jennifer" => "f", "Catherine" => "f", "Melissa" => "f", "Ian" => "m", "Max" => "m", "Zoe" => "f", "Stephen" => "m", "Justin" => "m", "Jesse" => "m", "Lily" => "f", "Victoria" => "f", "Aidan" => "m", "Madeline" => "f", "Eva" => "f", "Alison" => "f", "Paul" => "m", "Anthony" => "m", "Amy" => "f", "Chloe" => "f", "Natalie" => "f", "Jason" => "m", "Julian" => "m", "Mitchell" => "m", "Tess" => "f", "Henry" => "m", "Jackson" => "m", "Mary" => "f", "Colin" => "m", "Nathaniel" => "m", "Anne" => "f", "Patrick" => "m", "Danielle" => "f", "Isabel" => "f", "Simon" => "m", "Christina" => "f", "Christian" => "m", "Amanda" => "f", "Connor" => "m", "Angela" => "f", "Eli" => "m", "Bryan" => "m", "Brittany" => "f", "Kathryn" => "f", "Savannah" => "f", "Naomi" => "f", "Brian" => "m", "Brendan" => "m", "Kate" => "f", "Brandon" => "m", "Leah" => "f", "Erin" => "f", "Ali" => "f", "Alexis" => "f", "Madeleine" => "f", "Sophie" => "f", "Evan" => "m", "Margaret" => "f", "Kathleen" => "f", "Christine" => "f", "Morgan" => "f", "Sean" => "m", "Sophia" => "f", "Meghan" => "f", "Cameron" => "m", "Stephanie" => "f", "Timothy" => "m", "Miranda" => "f", "Avery" => ["b", 0.500], "Miriam" => "f", "Ashley" => "f", "Ella" => "f", "Hanna" => "f", "Philip" => "m", "Michelle" => "f", "Isaac" => "m", "Megan" => "f", "Isabella" => "f", "Jake" => "m", "Tyler" => "m", "Nathan" => "m", "Steven" => "m", "Ariel" => "f", "Susan" => "f", "Andrea" => "f", "Caitlin" => "f" }


# Merge all of our hashes form each class year and graduate programs into one hash,
# and write the data out so we don't have to query the database every time the program
# is run.
$merged_names = Hash.new(0)

(2015..2018).each do |y|
  CSV.open(".raw_names_" + y.to_s + ".csv", "wb") do |csv|
    $names_by_year[y].to_a.each do |pair|
      csv << pair
    end
  end
  $merged_names = $merged_names.merge($names_by_year[y]){|key, old, new| old + new}
end

CSV.open(".raw_names_other.csv", "wb") do |csv|
  $non_undergrad_names.to_a.each do |pair|
    csv << pair
  end
end
$merged_names = $merged_names.merge($non_undergrad_names){|key, old, new| old + new}

# There is a bug either in the database or in Mechanize; 
# a student named Matthew Metros comes back with the first name
# "Matthew " (with a trailing space).

$merged_names["Matthew"] += 1
$merged_names.delete("Matthew ")

# If the user requests that names be sorted into categories of similar
# spelling, merge different names under a shortened header
case mode
when 3
  $csv_string = "./names_categorized.csv"

  name_categories = Hash.new(0)
  
  $merged_names.each{|name, count|
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

# Alternatively, sort them by gender
when 4
  $csv_string = "./male_names.csv and ./female_names.csv"

  male_names = Hash.new(0)
  female_names = Hash.new(0)

  $merged_names.each{|name, count|
    if gender_categories.has_key? name
      if gender_categories[name][0] == "m"
        male_names[name] += count.to_i
      elsif gender_categories[name][0] == "f"
        female_names[name] += count.to_i
      else
        male_count = (gender_categories[name][1] * count).round
        female_count = count - male_count
        male_names[name] += male_count
        female_names[name] += female_count
      end
    end
  }

  $male_sorted_counts = male_names.to_a.sort_by{|n| n[1]}.reverse
  $female_sorted_counts = female_names.to_a.sort_by{|n| n[1]}.reverse

  # Write the data to disk
  CSV.open("male_names.csv", "wb") do |csv|
    $male_sorted_counts.each do |pair|
      csv << pair
    end
  end

  CSV.open("female_names.csv", "wb") do |csv|
    $female_sorted_counts.each do |pair|
      csv << pair
    end
  end
# If the user only asks for one class, only sort that class's hash
when 5
  $csv_string = "names_class_" + $year.to_s + ".csv"

  # Sort by names by frequency, descending
  $sorted_counts = $names_by_year[$year].to_a.sort_by{|n| n[1]}.reverse

  # Write the data to disk and distinguish the class
  CSV.open("names_class_" + $year.to_s + ".csv", "wb") do |csv|
    $sorted_counts.each do |pair|
      csv << pair
    end
  end

# If the user asks for both gender sorting and spelling merging,
# do both
when 6
  $csv_string = "./male_names_categorized_" + $year.to_s +
    ".csv and ./female_names_categorized_" + $year.to_s + ".csv"

  #First, split up the hashmap into gender lists

  male_names = Hash.new(0)
  female_names = Hash.new(0)

  $names_by_year[$year].each{|name, count|
    if gender_categories.has_key? name
      if gender_categories[name][0] == "m"
        male_names[name] += count.to_i
      elsif gender_categories[name][0] == "f"
        female_names[name] += count.to_i
      else
        male_count = (gender_categories[name][1] * count).round
        female_count = count - male_count
        male_names[name] += male_count
        female_names[name] += female_count
      end
    end
  }

  male_names_categorized = Hash.new(0)
  female_names_categorized = Hash.new(0)

  # Then merge each gender's list on spelling
  male_names.each{|name, count|
    if alternate_spellings.has_key? name
      male_names_categorized[alternate_spellings[name]] += count.to_i
    else
      male_names_categorized[name] += count.to_i
    end
  }

  female_names.each{|name, count|
    if alternate_spellings.has_key? name
      female_names_categorized[alternate_spellings[name]] += count.to_i
    else
      female_names_categorized[name] += count.to_i
    end
  }

  # sort them by popularity
  $male_sorted_counts = male_names_categorized.to_a.sort_by{|n| n[1]}.reverse
  $female_sorted_counts = female_names_categorized.to_a.sort_by{|n| n[1]}.reverse

  # Write the data to disk
  CSV.open("male_names_categorized_" + $year.to_s + ".csv", "wb") do |csv|
   $male_sorted_counts.each do |pair|
      csv << pair
    end
  end

  CSV.open("female_names_categorized_" + $year.to_s + ".csv", "wb") do |csv|
    $female_sorted_counts.each do |pair|
      csv << pair
    end
  end
# Otherwise, just sort the merged hashmap by popularity
else
  $csv_string = "names.csv"

  # Sort by names by frequency, descending
  $sorted_counts = $merged_names.to_a.sort_by{|n| n[1]}.reverse

  # Write the data to disk, if it wasn't there already
  if !File.exist? "names.csv"
    CSV.open("names.csv", "wb") do |csv|
      $sorted_counts.each do |pair|
        csv << pair
      end
    end
  end
end

# Print the input to the terminal, and tell the user where the data is written
case mode
when 1,2
  puts "\nTop 25 first names at Wes:\n"
when 3
  puts "\nTop 25 first name categories at Wes\n"
when 5
  puts "\nTop 25 first names in the Class of " + $year.to_s + "\n"
end

case mode
when 4
  puts "\nTop 25 'male' names at Wes\n"
  (0..24).each do |i|
    puts "#{i+1}: #{$male_sorted_counts[i][0]} (#{$male_sorted_counts[i][1]})"
  end

  puts "\nTop 25 'female' names at Wes\n"
  (0..24).each do |i|
    puts "#{i+1}: #{$female_sorted_counts[i][0]} (#{$female_sorted_counts[i][1]})"
  end
when 6
  puts "\nTop 25 'male' name categories in the Class of " + $year.to_s + "\n"
  (0..24).each do |i|
    puts "#{i+1}: #{$male_sorted_counts[i][0]} (#{$male_sorted_counts[i][1]})"
  end

  puts "\nTop 25 'female' name categories in the Class of " + $year.to_s + "\n"
  (0..24).each do |i|
    puts "#{i+1}: #{$female_sorted_counts[i][0]} (#{$female_sorted_counts[i][1]})"
  end
else
  (0..24).each do |i|
    puts "#{i+1}: #{$sorted_counts[i][0]} (#{$sorted_counts[i][1]})"
  end
end
puts "\nThis information has also been written to " + $csv_string + "."
