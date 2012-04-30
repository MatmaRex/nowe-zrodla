# coding: utf-8
require 'sunflower'
require 'time'
require 'pp'
require 'io/console'

# Notifies user / wikiproject about error report in articles.
# 
# articles is array of [title, [categories...]]
def notify_user_zb ns, page, articles
	ns_to_talk = {
		'Wikipedysta' => 'Dyskusja wikipedysty',
		'Wikipedystka' => 'Dyskusja wikipedysty',
		'Wikiprojekt' => 'Dyskusja Wikiprojektu',
	}
	
	p = Page.new "#{ns_to_talk[ns]}:#{page}"
	
	header = "== Nowy wpis na Zgłoś błąd =="
	add_header = p.text.scan(/==[^\n]+==/)[-1] != header # jesli ostatni naglowek jest nasz, nie powtarzamy go
	
	signature = "[[Wikipedysta:Powiadomienia ZB|Powiadomienia ZB]] ([[Wikipedia:Zgłoś błąd w artykule/Powiadomienia|informacje]]) ~~"+"~~"+"~"
	
	lines = []
	articles.each do |title, cats|
		line = [
			"Zgłoszono błąd w artykule [[#{title}]]",
			"(kategori#{cats.length>1 ? 'e' : 'a'}: #{cats.map{|c| "[[:#{c}|]]"}.join(", ") })",
			"–",
			"[[Wikipedia:Zgłoś błąd w artykule##{title}|zobacz wpis]]."
		].join ' '
		
		lines << line
	end
	
	p.text.rstrip!
	p.text += "\n\n"
	p.text += header+"\n" if add_header
	p.text += lines.join("\n\n")
	p.text += " "+signature
	
	summary_links = articles.map{|t,c| "[[Wikipedia:Zgłoś błąd w artykule##{t}|#{t}]]" }.join(', ')
	p.save p.title, "powiadomienie o nowych wpisach na Zgłoś błąd – #{summary_links}"
end




$stdout.sync = $stderr.sync = true

# $stderr.puts 'Input password:'
# $s = s = Sunflower.new('pl.wikipedia.org').login('Powiadomienia ZB', STDIN.noecho(&:gets).strip)
$s = s = Sunflower.new.login
s.summary = 'powiadomienie o braku źródeł w artykule (test)'

Thread.abort_on_exception = true

# Delay between creation of an article and notification, in seconds.
NOTIFY_DELAY = 60*15

queue = []

list_since = (Time.now.utc-NOTIFY_DELAY).iso8601
producer_thread = Thread.new do
	while true
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
	end
end

consumer_thread = Thread.new do
	while true
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
		elsif p.text =~ /bibliografia|źródł[ao]|literatura/i
			why = 'willdo'
		elsif p.text =~ /przypisy/i and p.text =~ /<ref/
			why = 'perfect'
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
		
		puts "Consumer[#{Time.now.utc.iso8601}]: done. Sleeping..."
	end
end

producer_thread.join
consumer_thread.join
