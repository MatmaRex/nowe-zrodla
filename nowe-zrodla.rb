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

list_since = Time.now.utc.iso8601
producer_thread = Thread.new do
	while true
		puts Time.now
		
		new = s.API p "action=query&list=recentchanges&rcnamespace=0&rcprop=title|user|timestamp&rcshow=!bot|!redirect&rclimit=500&rctype=new&rcstart=#{list_since}&rcdir=newer"
		
		Thread.exclusive do
			queue += new['query']['recentchanges']
		end
		
		list_since = Time.now.utc.iso8601
		
		p new
		
		sleep NOTIFY_DELAY
	end
end

consumer_thread = Thread.new do
	while true
		sleep 1 while queue.empty?
		
		h = nil
		Thread.exclusive do
			h = queue.shift
		end
		p h
		
		p (Time.now.utc-NOTIFY_DELAY).iso8601
		p h['timestamp']
		sleep 1 until (Time.now.utc-NOTIFY_DELAY).iso8601 >= h['timestamp']
		
		p = Page.new h['title']
		
		list = Page.new 'Wikipedysta:Matma_Rex/nowe bez źródeł'
		
		if p.text == ''
			list.text += "\n\nPowstał nowy artykuł wikipedysty [[User:#{h['user']}]] o nazwie [[#{h['title']}]], ale już go usunięto."
		elsif p.text =~ /bibliografia|przypisy|źródł[ao]|literatura/i
			list.text += "\n\nPowstał nowy artykuł wikipedysty [[User:#{h['user']}]] o nazwie [[#{h['title']}]], wygląda okej."
		else
			if p.text =~ /\{\{ek/i
				list.text += "\n\nOstrzegłbym wikipedystę [[User:#{h['user']}]] o braku źródeł w artykule [[#{h['title']}]], ale jest tam już EK."
			elsif p.text =~ /\A#(patrz|redirect|przekieruj)/i
				list.text += "\n\nOstrzegłbym wikipedystę [[User:#{h['user']}]] o braku źródeł w artykule [[#{h['title']}]], ale wygląda on na przekierowanie."
			elsif p.text =~ /linki zewn/i
				list.text += "\n\nOstrzegłbym wikipedystę [[User:#{h['user']}]] o braku źródeł w artykule [[#{h['title']}]], ale ma on przynajmniej linki zewnętrzne."
			else
				list.text += "\n\nOstrzegłbym wikipedystę [[User:#{h['user']}]] o braku źródeł w artykule [[#{h['title']}]]."
			end
			
			puts 'woo'
		end
		
		list.save if list.text != list.orig_text
	end
end

producer_thread.join
consumer_thread.join
