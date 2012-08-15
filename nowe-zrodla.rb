# coding: utf-8
require 'sunflower'
require 'time'
require 'pp'
require 'io/console'

def drop_a_message talkpage, header, message, summary=header
	p = Page.new talkpage
	
	p.text.rstrip!
	p.text += "\n\n"
	p.text += "== #{header} =="+"\n"
	p.text += message
	
	p.save p.title, summary
end

$stdout.sync = $stderr.sync = true

$stderr.puts 'Input password:'
s = Sunflower.new('pl.wikipedia.org').login('MatmaBot', STDIN.noecho(&:gets).strip)
s.summary = nil # ensure we can't save unless summary for edit given

Thread.abort_on_exception = true

# Delay between creation of an article and notification, in seconds.
NOTIFY_DELAY = 60*45

queue = []

list_since = (Time.now.utc-NOTIFY_DELAY).iso8601
producer_thread = Thread.new do
	while true
		begin
			puts "Producer[#{Time.now.utc.iso8601}]: checking RC."
			
			new = s.API(
				action: 'query',
				list: 'recentchanges', rclimit: 500,
				rctype: 'new', 
				rcnamespace: 0, rcprop: 'title|user|timestamp', rcshow: '!bot|!redirect',
				rcdir: 'newer', rcstart: list_since
			)
			
			puts "Producer[#{Time.now.utc.iso8601}]: adding #{new['query']['recentchanges'].length} new to queue."
			Thread.exclusive do
				queue += new['query']['recentchanges']
			end
			
			list_since = Time.now.utc.iso8601
			
			sleep NOTIFY_DELAY
			
		rescue Exception
			puts "Producer[#{Time.now.utc.iso8601}]: connection error. Retrying in 20 seconds..."
			sleep 20
			retry
		end
	end
end

consumer_thread = Thread.new do
	while true
		begin
			sleep 10 while queue.empty?
			
			h = nil
			Thread.exclusive do
				h = queue.shift
			end
			
			puts "Consumer[#{Time.now.utc.iso8601}]: got an article #{h['title']}"
			puts "Consumer[#{Time.now.utc.iso8601}]: article created at #{h['timestamp']}, waiting..."
			sleep 10 until (Time.now.utc-NOTIFY_DELAY).iso8601 >= h['timestamp']
			
			puts "Consumer[#{Time.now.utc.iso8601}]: time to handle #{h['title']}"
			
			p = Page.new h['title']
			
			dowarn = false
			why = ''
			
			if p.text == ''
				why = 'deleted'
			elsif p.text =~ /(?:\{\{|==+ *)przypisy|<references/i and p.text =~ /<ref/
				why = 'perfect'
			elsif p.text =~ /\{\{(szablon|template|)zwierzę infobox[\s\S]+\|\s*TSN\s*=\s*\d+/i
				why = 'magicznerefy'
			elsif p.text =~ /bibliografia|[źżz]ródł[ao]|literatura/i
				why = 'willdo'
			else
				if p.text =~ /\{\{ek/i
					why = 'EK'
				elsif p.text =~ /\{\{disambig\}\}/i
					why = 'disambig'
				elsif p.text =~ /\A#(patrz|redirect|przekieruj)/i
					why = 'redirect'
				elsif p.text =~ /linki zewn/i
					why = 'linki zewn'
				else
					why = 'no sources!'
					dowarn = true
				end
			end
			
			puts "Consumer[#{Time.now.utc.iso8601}]: article state: #{why}"
			
			if dowarn
				puts "Consumer[#{Time.now.utc.iso8601}]: warning user #{h['user']}..."
				volunteers = File.readlines('ochotnicy.txt')
				
				heading = "Prośba o źródła w artykule [[#{h['title']}]]"
				message = "{{pamiętaj o źródłach|#{h['title']}|#{volunteers.sample.strip}}}"
				drop_a_message "User talk:#{h['user']}", heading, message
			end
			
			puts "Consumer[#{Time.now.utc.iso8601}]: done. Sleeping..."
			
		rescue Exception
			Thread.exclusive do
				queue << h
			end
			
			puts "Consumer[#{Time.now.utc.iso8601}]: connection error. Retrying in 20 seconds..."
			puts "Consumer[#{Time.now.utc.iso8601}]: (current article, #{h['title']}, moved to the end of queue)"
			sleep 20
			retry
		end
	end
end

producer_thread.join
consumer_thread.join
