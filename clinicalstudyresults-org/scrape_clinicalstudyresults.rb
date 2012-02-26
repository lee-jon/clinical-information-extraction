#!/usr/bin/env ruby
# scrape_clinicalstudyresults.rb

# Scraping http://www.clinicalstudyresults.org
# using Hpricot and open-uri
# 
# Script scrapes the ids of all the drugs available from a dropdown.
# Each page for the individual drug_id is then scraped into a database.

# Step 0: Setup
# Step 1: Scan the site for the list of unique drug_id's
# Step 2: Iterate Step 3 for each drug_id
# Step 3: Scan page 1 for the number of entires and calculate pages
#       + Scrape the table into the "results" array
#       + Repeat for each page
#       + Scrape the deeper page correct the summary and download PDFs
#       + Reformat the scrap of the drug_id into tables and add to the entry_table array
# Step 4: Dump the entry_table array into a CSV file
# Step 5: Announce completion

# Created Oct 2011: Dr. Lee-Jon Ball
# leejonball@gmail.com

# Gems required. If hpricot fails do 'gem install hpricot'
require 'rubygems'  # Gems package manager
require 'open-uri'  # HTTP parser http://stdlib.rubyonrails.org/libdoc/open-uri/rdoc/index.html
require 'hpricot'   # whytheluckystiff's HTML hhttp://rubydoc.info/github/hpricot/hpricot
require 'csv'       # CSV parser

#####
# STEP 0: Setup global variables
#####
entry_table = []
start_time = Time.now
list_of_drug_names = []
list_of_drug_ids =[]

#####
# STEP 1: Obtain the start page and scan for the list of drugs
#####

doc = Hpricot(open("http://www.clinicalstudyresults.org/search/"))
(doc/"/html/body/table[5]/tr/td[2]/table/tr/td[2]/table/tr/td[2]/table/tr[3]/td/table/tr[2]/td[2]/select/option").each do |option| # For some reason select.drug_name_id isn't working?! 
  #  input = option.to_html.scan(/(?:<option value=")(.*)(?:")/)
  scan_for_drug_id = option.to_html.scan(/\d+(?=")/)
  list_of_drug_ids << scan_for_drug_id[0]
  list_of_drug_names << [scan_for_drug_id[0], option.inner_html]
end

# Save the list of drugs that will be scanned
CSV.open("list_of_drugs.csv", "w") do |csv|
  csv << list_of_drug_names
end

#####
# STEP 2: Begin iterating over drug_ids
#####
list_of_drug_ids.each do |drug_number|

  # 2.0 Each drug iteration uses the following variables
  drug_id = drug_number
  page_id = 1
  row_array = []
  result = []
  
  # Uncomment for logging text
  puts "Beginning scrape of drug_id #{drug_number}"
  
  # 2.1 Start with the first page and get request http using open-uri  
  @url = "http://www.clinicalstudyresults.org/search/?drug_name_id=" + drug_id.to_s + "&r=1&submitted=1&page=" + page_id.to_s
  @response = ""
  open(@url, "User-Agent" => "Ruby/#{RUBY_VERSION}") { |f|
    @response = f.read
  }
    
  # Give response from http request to Hpricot
  doc = Hpricot(@response)
  
  # Scrape the number of entries and calculate the pages for this entry
  count_of_entries = (doc/"html/body/table[5]/tr/td[2]/table/tr/td[2]/table/tr/td[2]/table/tr[2]/td/p/b[3]").inner_html.to_i
  number_remaining = count_of_entries
  number_of_pages = (count_of_entries.to_f/10).ceil
  
  # Scrape the data on page 1
    (doc/"td.results_lower").each do |i| 
    result << i.inner_html
  end
  
  # Scape the data on pages 2..n
  if number_of_pages > 1
    (2..number_of_pages).each do |page_id|
      @url = "http://www.clinicalstudyresults.org/search/?drug_name_id=" + drug_id.to_s + "&r=1&submitted=1&page=" + page_id.to_s
      open(@url, "User-Agent" => "Ruby/#{RUBY_VERSION}") { |f|
        @response = f.read
      }
      doc = Hpricot(@response)
      (doc/"td.results_lower").each do |i| 
        result << i.inner_html
      end
    end
  end
  
  # Scraper just outputs a log list in an array, this extracts it to a array of arrays
  # BUG This is very stupidly clunky but it works
  (0..count_of_entries-1).each do |row|
    
    # Put the record into a single row
    row_array =[]
    (0..9).each do |column|
      row_array << result[(row*10)+column]
    end
    
    # Get the deeper link
    contents = Hpricot(row_array[9])
    
    (contents/"//a").each do |link|
      href_text = link.attributes['href']
      @url = "http://www.clinicalstudyresults.org" + href_text
    end
    
    # scrape the deeper page
    open(@url, "User-Agent" => "Ruby/#{RUBY_VERSION}") { |f|
      @response = f.read
    }
    doc = Hpricot(@response)
    summary = (doc/"/html/body/table[5]/tr/td[2]/table/tr/td[2]/table/tr/td[2]/table/tr[2]/td/table[2]/tr[3]/td[2]").inner_html
    
    # Get the pdf files
    downloaded_files = []
    (doc/"/html/body/table[5]/tr/td[2]/table/tr/td[2]/table/tr/td[2]/table/tr[2]/td/table[2]/tr[4]/td[2]/table/tr/td[2]/a").each do |link|
      wget_pdf = link.attributes['href'].gsub("%2F", "/") 
      filename = File.basename(wget_pdf)
      downloaded_files << filename
      @url = "http://www.clinicalstudyresults.org/documents/" + filename
      open(filename, "wb") do |file|
        begin
        file.print open(@url).read
        rescue => e
          case e
          when OpenURI::HTTPError 
            error = "***ERROR***: #{filename} is giving a -- #{e} -- exception"
            downloaded_files << error
          when SocketError
            error = "**ERROR***: #{filename} is giving a -- #{e} -- exception"
            downloaded_files << error
          end
          
          rescue SystemCallError => e
            if e === Errno::ECONNRESET
              error = "**ERROR***: #{filename} is giving a -- #{e} -- exception"
              downloaded_files << error
            else
              raise e
            end
          end  
        end 
      end        

    
    # Add the PDFs to 
    row_array[8] = summary
    row_array[9] = downloaded_files
    puts "Downloading now includes the files #{row_array[9]}"    
    entry_table << row_array  
  end  # Iterate the next row
  
  # Uncomment the following lines if you want to watch each scrape in the terminal 
  puts "Scrape of #{drug_id} completed at #{Time.now} with #{count_of_entries} records"
  puts "Entry_table written for drug_id: #{drug_id} and is now size: #{entry_table.size}"
  puts "  "
end # Now iterate the next 


#####
# STEP 4: Output the massive array to a CSV file
#####
CSV.open("clinical_study_results.csv", "w") do |csv|
  puts "RESULT  : "
  csv << ["Company Name" , "Business Partner", "Drug Name", "Generic Name", "Unique ID", "Studied Indications or Disease", "Phase", "Approved Drug Label", "Clinical Study Summary", "Files downloaded"]
  (0..entry_table.size-1).each do |row| 
    csv << entry_table[row]
  end
  puts "CSV output complete"
end

#####
# STEP 5: Announce completion!
#####
puts "Scrape complete @: #{Time.now}"
puts "Time taken       : #{Time.now - start_time} s"