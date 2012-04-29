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


# list_since = Marshal.load File.binread 'last_check-marshal' rescue Time.now.utc.to_s
list_since = Time.now.utc.iso8601

while true
	puts Time.now
	
	new = s.API p "action=query&list=recentchanges&rcnamespace=0&rcprop=title|user|timestamp&rcshow=!bot|!redirect&rclimit=500&rctype=new&rcstart=#{list_since}&rcdir=newer"
	
	list_since = Time.now.utc.iso8601
	
	p new
	
	new['query']['recentchanges'].each do |h|
		p = Page.new h['title']
		
		p h
		
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
	
	sleep 60*10
end
