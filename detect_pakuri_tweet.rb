#-*- coding: utf-8 -*-

require 'cgi'
require 'sqlite3'
require 'net/http'

Plugin.create(:detectpakuri) do

  @table = "detectpakuri"
  @dbfile = @table + ".db"
  @retweet_thresh = 3
  @tweetchar_thresh = 80

  @ignore_string = [" ", "　", "\n", "#{Post.primary_service.user}"]
  @blacklist = ["omosiro_tweet", "1000favs", "500favs", "250favs", "1000Retweets", "favGazo", "omoshiro_kopipe", "omykd", "shokai_twit"]

  @registeralltweets = false
  @retweetmessage = false
  @favoritemessage = true
  @tweetdetection = false
  @stop = false


  def self.createSystemMessage(message)
    Plugin.call(:update, nil, [Message.new(:message => "#{message}", :system => true)])
  end


  def self.findDatabaseById(tweetid)
    db = SQLite3::Database.new(@dbfile)
    list = db.execute("select * from #{@table} where tweetid = #{tweetid}")
    db.close()
    return list
  end


  def self.tweetDetection(message, tweetid, tweet = @tweetdetection)
    username = findDatabaseById(tweetid)[0][2]

    str = "【パクリ検出】〄#{message.idname} が " +
      "〄#{username} のツイートをパクった可能性があります\n" +
      "もとのツイート: https://twitter.com/#!/#{username}/status/#{tweetid.to_s}\n" +
      "パクリ容疑: https://twitter.com/#!/#{message.user}/status/#{message.id}\n" +
      "#detectpakuritweet"

    if tweet then
      Post.primary_service.post :message => str
    else
      createSystemMessage(str)
    end

    if @retweetmessage then
      message.retweet
    end

    if @favoritemessage then
      message.favorite(true)
    end

  end


  def self.checkCopied(message, tweet = @tweetdetection)
    Thread.new {
      if !message.system? then

        if message.retweet? then
          src = message.retweet_source(true)
          if src then
            message = src
          end
        end

        regmsg = message.to_s
        @ignore_string.each do |str|
          regmsg = regmsg.gsub("#{str}", '')
        end

        db = SQLite3::Database.new(@dbfile)
        escapestr = CGI.escape(regmsg).gsub('%','')
        list = db.execute("select * from #{@table} where message = '#{escapestr}'")
        db.close()

        isCopied = (list.length != 0 and (list[0][2].to_s != message.user.to_s))

        if isCopied == true and
            not message.to_s =~ /(@|＠)#{list[0][2]}/ then

          Plugin.call(:pakuraredetected, message, Message.findbyid(list[0][0]))
          tweetDetection(message, list[0][0], tweet)
        end

      end
    }
  end

  def self.isControlMessage?(message)
    if !message.from_me? or message.retweet? or
        Time.now - message[:created] >= 5 then
      return false
    else
      control = false
      if message.to_s =~ /(パクリ|ぱくり)検出公開/ then
        @tweetdetection = true
        createSystemMessage("TweetDetection = #{@tweetdetection}")
        control = true
      end
      if message.to_s =~ /(パクリ|ぱくり)検出非公開/ then
        @tweetdetection = false
        createSystemMessage("TweetDetection = #{@tweetdetection}")
        control = true
      end
      if message.to_s =~ /晒しRTせっと/ then
        @retweetmessage = true
        createSystemMessage("RetweetSource = #{@retweetmessage}") 
        control = true
      end
      if message.to_s =~ /晒しRTあんせっと/ then
        @retweetmessage = false
        createSystemMessage("RetweetSource = #{@retweetmessage}")
        control = true
      end
      if message.to_s =~ /検出ふぁぼせっと/ then
        @favoritemessage = true
        createSystemMessage("FavoriteMessage = #{@favoritemessage}")
        control = true
      end
      if message.to_s =~ /検出ふぁぼあんせっと/ then
        @favoritemessage = false
        createSystemMessage("FavoriteMessage = #{@favoritemessage}")
        control = true
      end
      if message.to_s =~ /全部DBに登録/ then
        @registeralltweets = true
        createSystemMessage("RegisterAllTweets = #{@registeralltweets}")
        control = true
      end
      if message.to_s =~ /自分のだけDBに登録/ then
        @registeralltweets = false
        createSystemMessage("RegisterAllTweets = #{@registeralltweets}")
        control = true
      end
      if message.to_s =~ /(パクリ|ぱくり)?検出停止/ then
        @stop = true
        createSystemMessage("検出を停止しました")
        control = true
      end
      if message.to_s =~ /(パクリ|ぱくり)?検出再開/ then
        @stop = false
        createSystemMessage("検出を再開しました")
        control = true
      end
      if message.to_s =~ /検出文字数レベル (\d+)/ then
        @tweetchar_thresh = $1.to_i
        createSystemMessage("検出する文字数のしきい値を #{@tweetchar_thresh} に設定しました")
        control = true
      end
      if message.to_s =~ /検出DBりせっと/ then
        db = SQLite3::Database.new(@dbfile)
        db.execute("delete from #{@table} where tweetid > 0")
        db.close()
        createSystemMessage("パクリ検出DBを全消去しました")
        control = true
      end
      if message.to_s =~ /検出RTレベル (\d+)/ then
        @retweet_thresh = $1.to_i
        createSystemMessage("パクリ検出DBに追加するRTレベル #{@retweet_thresh} にセットしました")
        control = true
      end
      return control
    end
  end


  def self.registerMessage(message, echo = false, isretweet = false)
    Thread.new {
      db = SQLite3::Database.new(@dbfile)
      list = db.execute("select tweetid from #{@table} where tweetid = #{message.id.to_s}") 

      str = message.to_s
      @ignore_string.each do |s|
        str = str.gsub(s, '')
      end

      if list.length == 0 then
        sql = "insert into #{@table} values (#{message.id.to_s}, '#{CGI.escape(str).gsub('%','')}', '#{message.user.to_s}')"
        db.execute(sql)

        if echo or isretweet then
          createSystemMessage("ツイートをパクリ検出DBに登録しました:\n" +
                              "#{message.to_s}\n" +
                              "https://twitter.com/#!/#{message.user}/status/#{message.id.to_s}")
        end

      else
        if echo then
          createSystemMessage("既にパクリ検出DBに登録済です")
        end
      end

      db.close()
    }
  end

  def self.unregisterMessage(message)
    Thread.new {
      db = SQLite3::Database.new(@dbfile)
      db.execute("delete from #{@table} where tweetid = #{message.id.to_s}")
      db.close()
      createSystemMessage("ツイートをパクリ検出DBから削除しました:\n" +
                            "https://twitter.com/#!/#{message.user}/status/#{message.id.to_s}")
    }
  end

  def processBlackList(message)
    Thread.new {
      message.to_s =~ / ([A-Za-z0-9_]+)$/
      username = $1
      favstarpage = Net::HTTP.get('favstar.fm', "/users/#{username}.html")

      most = favstarpage.scan(/<div class=\"theTweet\">[\S\s]*?<a class=\"bird\"[\S\s]*?<\/a>/)
      if most then
        most.each do |s|
          src = CGI.unescape(CGI.escape(s)).gsub(/\s/,'').gsub('<br>','').gsub('　', '').gsub(/<ahref=\S+?<\/a>/,'')
          index = (src =~ /#{message.to_s.gsub(/https?:\S+/,'').gsub(" #{username}", '').gsub(/\s/, '').gsub('　', '').gsub("\n", '')}/)
          if index != nil then
            src =~ /aclass=\"bird\"[\S\s]*?http:[^\"]+status\/([0-9]+)/
            tweetid = $1
            str = "【奇跡の一致検出】〄#{message.user} と " +
              "〄#{username} のツイートが奇跡的な一致をしています！\n" +
              "オリジナル: https://twitter.com/#!/#{username}/status/#{tweetid.to_s}\n" +
              "奇跡の一致: https://twitter.com/#!/#{message.user}/status/#{message.id.to_s}\n" +
              "#detectpakuritweet"
            Post.primary_service.post :message => str
            break
          end
        end
      end
    }
  end

  on_appear do |messages|
    messages.each{ |m|
      Thread.new do
        if !m.system? then

          if m.from_me? then
            control = isControlMessage?(m)
          elsif @blacklist.select{|x| x == m.user.to_s}.length > 0 then
            processBlackList(m)
          end

          if !@stop then

            if @registeralltweets then
              if m.retweet? then
                m = m.retweet_source(true)
              end
              if m.to_s.length >= @tweetchar_thresh then
                registerMessage(m)
              end
            end

            if !control then
              checkCopied(m)
            end

          end

        end
      end
    }
  end

  on_retweet do |messages|
    messages.each{ |m|
      Thread.new do
        if !m.system? and !@stop then
          src = m.retweet_source(true)
          if src.from_me? and src.retweeted_by.length >= @retweet_thresh then
            registerMessage(src, false, true)
          end
        end
      end
    }
  end


  on_boot do |service|
    db = SQLite3::Database.new(@dbfile)
    existsTable = db.execute('select * from sqlite_master').size >= 1
    if not existsTable then
      db.execute("create table #{@table} (tweetid, message, username)")
    end
    db.close()
  end


 add_event_filter(:command){ |menu|
    menu[:register_tweet] = {
      :slug => :register_tweet,
      :name => 'このツイートをパクリ検出DBに登録',
      :condition => lambda{ |m| !m.message.system? },
      :exec => lambda{ |m| registerMessage(m.message, true) },
      :visible => true,
      :role => :message }
    [menu]
  }

  add_event_filter(:command){ |menu|
    menu[:unregister_tweet] = {
      :slug => :unregister_tweet,
      :name => 'このツイートをパクリ検出DBから削除',
      :condition => lambda{ |m| !m.message.system? },
      :exec => lambda{ |m| unregisterMessage(m.message) },
      :visible => true,
      :role => :message }
    [menu]
  }

  add_event_filter(:command){ |menu|
    menu[:check_pakurare] = {
      :slug => :check_pakurare,
      :name => 'このツイートパクられじゃないの？',
      :condition => lambda{ |m| !m.message.system? },
      :exec => lambda{ |m| checkCopied(m.message, true) },
      :visible => true,
      :role => :message }
    [menu]
  }

  add_event_filter(:command){ |menu|
    menu[:process_blacklist] = {
      :slug => :process_blacklist,
      :name => 'ブラックリストのアカウントとして処理',
      :condition => lambda{ |m| !m.message.system? },
      :exec => lambda{ |m| processBlackList(m.message) },
      :visible => true,
      :role => :message }
    [menu]
  }


end
