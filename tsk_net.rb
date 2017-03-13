# coding: utf-8

require 'rubygems'
require 'nkf'
require 'net/http'
Net::HTTP.version_1_2
require 'rexml/document'
require 'time'
require 'digest/sha1'
require 'optparse'

require './lib/tenco_reporter/config_util'
include TencoReporter::ConfigUtil
require './lib/tenco_reporter/track_record_util'
include TencoReporter::TrackRecordUtil
require './lib/tenco_reporter/update_check'
include TskNet::UpdateCheck
require './lib/tenco_reporter/config_locale'

# Some conditions to affect program behavior
$is_force_insert = false # Forced insert mode. Set to false when getting started
$is_all_report = false # Upload all mode
$updateCheck = false # Detect update check
$is_new_account = false # New account or login
$is_account_register_finish = false # Detect if there is a account signed up

### Load config to memory ###
# Set config file path
$config_file = 'config.yaml'
$config_default_file = 'config_default.yaml'
$env_file = 'env.yaml'
$var_file = 'variables.yaml'

# If tsk net config file was missing, print an error and exit program.
unless (File.exist?($env_file) && File.exist?($var_file) && File.exist?($config_file))
  puts "Error: one or more config files were missing"
  # Print all the config status on screen to help debugging
  puts $config_file
  puts File.exist?($config_file)
  puts $env_file
  puts File.exist?($env_file)
  puts $var_file
  puts File.exist?($var_file)
  puts "Press Enter to exit."
  
  gets
  exit
end

# Read config to RAM
$config = load_config($config_file) 
$env = load_config($env_file)
$variables = load_config($var_file)

# User account and password
$account_name = ""
$account_password = ""

# Database file path
$db_file_path = $config['database']['file_path'].to_s || $variables['DEFAULT_DATABASE_FILE_PATH']
  
# Tenco service edition(tenco.info/2, /5 etc)
$game_id = $variables['DEFAULT_GAME_ID']


# Seems these variables were used to find server.
# SERVER_TRACK_RECORD
$SERVER_TRACK_RECORD_HOST = $env['server']['track_record']['host'].to_s
$SERVER_TRACK_RECORD_ADDRESS = $env['server']['track_record']['address'].to_s
$SERVER_TRACK_RECORD_PORT = $env['server']['track_record']['port'].to_s
$SERVER_TRACK_RECORD_PATH = $env['server']['track_record']['path'].to_s
# SERVER_LAST_TRACK_RECORD
$SERVER_LAST_TRACK_RECORD_HOST = $env['server']['last_track_record']['host'].to_s
$SERVER_LAST_TRACK_RECORD_ADDRESS = $env['server']['last_track_record']['address'].to_s
$SERVER_LAST_TRACK_RECORD_PORT = $env['server']['last_track_record']['port'].to_s
$SERVER_LAST_TRACK_RECORD_PATH = $env['server']['last_track_record']['path'].to_s
# SERVER_ACCOUNT
$SERVER_ACCOUNT_HOST = $env['server']['account']['host'].to_s
$SERVER_ACCOUNT_ADDRESS = $env['server']['account']['address'].to_s
$SERVER_ACCOUNT_PORT = $env['server']['account']['port'].to_s
$SERVER_ACCOUNT_PATH = $env['server']['account']['path'].to_s
# CLIENT_LATEST_VERSION
$CLIENT_LATEST_VERSION_HOST = $env['client']['latest_version']['host'].to_s
$CLIENT_LATEST_VERSION_ADDRESS = $env['client']['latest_version']['address'].to_s
$CLIENT_LATEST_VERSION_PORT = $env['client']['latest_version']['port'].to_s
$CLIENT_LATEST_VERSION_PATH = $env['client']['latest_version']['path'].to_s
# CLIENT_SITE_URL
$CLIENT_SITE_URL = "http://#{$env['client']['site']['host']}#{$env['client']['site']['path']}"
# Default HTTP request header
$HTTP_REQUEST_HEADER = $variables['HTTP_REQUEST_HEADER'][0]
$HTTP_REQUEST_HEADER = {"User-Agent" => "Tensokukan Report Tool #{$variables['PROGRAM_VERSION']}"}
# Two different request header for obfs4 forward server.
$HTTP_REQUEST_HEADER_MAIN = $variables['HTTP_OBFS4_REQUEST_HEADER'][0]
$HTTP_REQUEST_HEADER_STATIC = $variables['HTTP_OBFS4_REQUEST_HEADER'][1]
# Vaild account name and email address characters, regular expression
$ACCOUNT_NAME_REGEX = /\A[a-zA-Z0-9_]{1,32}\z/
$MAIL_ADDRESS_REGEX = /\A[\x01-\x7F]+@(([-a-z0-9]+\.)*[a-z]+|\[\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\])\z/

# Etc

$RECORD_SW_NAME = $variables['RECORD_SW_NAME']
$DB_TR_TABLE_NAME = $variables['DB_TR_TABLE_NAME']
$DUPLICATION_LIMIT_TIME_SECONDS = $variables['DUPLICATION_LIMIT_TIME_SECONDS']
$TRACKRECORD_POST_SIZE = $variables['TRACKRECORD_POST_SIZE']
$PLEASE_RETRY_FORCE_INSERT = $variables['PLEASE_RETRY_FORCE_INSERT']
# Match result
$trackrecord = []
# Meaning unknown variables, keep original comments
$is_read_trackrecord_warning = false # 対戦結果読み込み時に警告があったかどうか
$is_warning_exist = false # 警告メッセージがあるかどうか
# Error Log path
$ERROR_LOG_PATH = $variables['ERROR_LOG_PATH']

###################################################
# Environments were loaded, below are program code.
###################################################
  
    
  
# Print program name and version and something else
# at the very beginning
puts "*** #{$variables['PROGRAM_NAME']} ***"
puts "ver.#{$variables['PROGRAM_VERSION']}, branch.#{$variables['PROGRAM_BRANCH_NAME']}"
puts
puts
puts

# Define some common methods
def saveConfigFile()
  # Update configuration file
  save_config($config_file, $config)
end
def printHTTPcode(response)
  puts "HTTP #{response.code}"
  puts
end
def parseLaunchArguments()
  ### Define available program launch options
  opt = OptionParser.new

  # If '-a' was specified
  # Mark upload all mode to true
  opt.on('-a') {|v| $is_all_report = true}

  # Parse the arguments
  opt.parse!(ARGV)
end
def importConfigToVariables()
  # The following code seems to read some value from config to variables
  
  ##################################################
  # Meaning unknown, keep original comments

  # config.yaml がおかしいと代入時にエラーが出ることに対する格好悪い対策
  $config ||= {}
  $config['account'] ||= {}
  $config['database'] ||= {}

  $account_name = $config['account']['name'].to_s || ''
  $account_password = $config['account']['password'].to_s || ''
   
  ##################################################
end
def doDebugAction()
  if $variables['DEBUG_EXIT']
    puts "Debug Action: Exit."
    exit
  end
end
def detectExistAccount()
  # My account detect method(simple ver)
  if $config['account']['name'] == ""
    $is_account_register_finish = false
  else
    $is_account_register_finish = true
  end
  # The old one account detect method(regulare expersion)
  # Run at the same time to prevent one of them not work.
  
  # != 0 means the account is not valid:
  if ($account_name =~ $ACCOUNT_NAME_REGEX) != 0
    $account_name = ''
    $account_password = ''
    $is_account_register_finish = false
  else
    $is_account_register_finish = true
  end
end
def doUpdateCheck()
  begin
    latest_version = get_latest_version($CLIENT_LATEST_VERSION_HOST, $CLIENT_LATEST_VERSION_PATH)
    
    case
    when latest_version.nil?
      puts "！最新バージョンの取得に失敗しました。"
      puts "スキップして続行します。"
    when latest_version > $variables['PROGRAM_VERSION'] then
      puts "★新しいバージョンの#{$variables['PROGRAM_NAME']}が公開されています。（ver.#{latest_version}）"
      puts "ブラウザを開いて確認しますか？（Nを入力するとスキップ）"
      print "> "
      case gets[0..0]
      when "N" then
        puts "スキップして続行します。"
        puts 
      else
        system "start #{$CLIENT_SITE_URL}"
        exit
      end
    when latest_version <= $variables['PROGRAM_VERSION'] then
      puts "お使いのバージョンは最新です。"
      puts 
    end
    
  # Print a message if update check was failed
  rescue => ex
    puts "！クライアント最新バージョン自動チェック中にエラーが発生しました。"
    puts ex.to_s
    # puts ex.backtrace.join("\n")
    puts ex.class
    puts
    puts "スキップして処理を続行します。"
    puts
  end
end
def doAccountSignUp()
  # 空两行
  puts "★新規 #{$variables['WEB_SERVICE_NAME']} アカウント登録\n\n"
    
  # While loop until successful signed up
  while (!$is_account_register_finish)
  # Enter account name
    puts "希望アカウント名を入力してください\n"  
    puts "アカウント名はURLの一部として使用されます。\n"  
    puts "（半角英数とアンダースコア_のみ使用可能。32文字以内）\n"  
    print "希望アカウント名> "  
    while (input = gets)
      input.strip!
      if input =~ $ACCOUNT_NAME_REGEX then
        $account_name = input
        puts 
        break
      else
        puts "！希望アカウント名は半角英数とアンダースコア_のみで、32文字以内で入力してください"  
        print "希望アカウント名> "  
      end
    end
    puts "Added account: #{$account_name}"
    puts
    
    # Enter password
    puts "パスワードを入力してください（使用文字制限なし。4～16byte以内。アカウント名と同一禁止。）\n"  
    print "パスワード> "  
    while (input = gets)
      input.strip!
      if (input.length >= 4 and input.length <= 16 and input != $account_name) then
        $account_password = input
        break
      else
        # Show some available warn
        if input == $account_name
          puts "Password must be different than account."
        end
        puts "！パスワードは4～16byte以内で、アカウント名と別の文字列を入力してください"  
        print "パスワード> "  
      end
    end
    puts
    puts "Added password: #{$account_password}"
    puts
    print "パスワード（確認）> "  
    while (input = gets)
      input.strip!
      if ($account_password == input) then
        puts 
        break
      else
        puts "！パスワードが一致しません\n"  
        print "パスワード（確認）> "  
      end
    end
    
    # Enter email address
    puts "メールアドレスを入力してください（入力は任意）\n"  
    puts "※パスワードを忘れたときの連絡用にのみ使用します。\n"  
    puts "※記入しない場合、パスワードの連絡はできません。\n"  
    print "メールアドレス> "  
    while (input = gets)
      input.strip!
      if (input == '') then
        account_mail_address = ''
        puts "メールアドレスは登録しません。"  
        puts
        break
      elsif input =~ $MAIL_ADDRESS_REGEX and input.length <= 256 then
        # Fix a potential problem
        # Add downcase for input
        
        # The script used to be hang up... I'm not sure
        # If a user Enter some uppercase after @ symbol
        # Few user met the problem and have not starting to debug
        
        # Since Tsk 2017 build 1
        account_mail_address = input.downcase
        puts
        break
      else
        puts "！メールアドレスは正しい形式で、256byte以内にて入力してください"  
        print "メールアドレス> "  
      end
    end
    
    # Register new account on server
    puts "サーバーにアカウントを登録しています..."
    puts  
    
    # Generate Account XML
    account_xml = REXML::Document.new
    account_xml << REXML::XMLDecl.new('1.0', 'UTF-8')
    account_element = account_xml.add_element("account")
    account_element.add_element('name').add_text($account_name)
    account_element.add_element('password').add_text($account_password)
    account_element.add_element('mail_address').add_text(account_mail_address)
    # Upload to server
    $response = nil
    # http = Net::HTTP.new($SERVER_ACCOUNT_HOST, 443)
    # http.use_ssl = true
    # http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http = Net::HTTP.new($SERVER_ACCOUNT_HOST, 80)
    http.start do |s|
      $response = s.post($SERVER_ACCOUNT_PATH, account_xml.to_s, $HTTP_REQUEST_HEADER)
    end
    
    print "サーバーからのお返事\n"  
    $response.body.each_line do |line|
      puts "> #{line}"
    end
  
    if $response.code == '200' then
      # Account registration success:
      $is_account_register_finish = true
      $config['account']['name'] = $account_name
      $config['account']['password'] = $account_password
      
      saveConfigFile()
      
      puts 
      puts "アカウント情報を設定ファイルに保存しました。"
      puts "サーバーからのお返事の内容をご確認ください。"
      puts
      puts "Enter キーを押すと、続いて対戦結果の報告をします..."
      gets
      
      puts "引き続き、対戦結果の報告をします..."
      puts
    else
    # Account registration failure:
      puts "もう一度アカウント登録をやり直します...\n\n"
      puts "Press Enter to retry."
      gets
    end
  end
end
def doAccountLogin()
  puts "★設定ファイル編集\n"
  puts "#{$variables['WEB_SERVICE_NAME']} アカウント名とパスワードを設定します"
  puts "※アカウント名とパスワードが分からない場合、ご利用の#{$variables['WEB_SERVICE_NAME']}クライアント（緋行跡報告ツール等）の#{$config_file}で確認できます"
  puts 
  puts "お持ちの #{$variables['WEB_SERVICE_NAME']} アカウント名を入力してください"
  
  # Enter account name
  print "アカウント名> "
  while (input = gets)
    input.strip!
    if input =~ $ACCOUNT_NAME_REGEX then
      $account_name = input
      puts 
      break
    else
      puts "！アカウント名は半角英数とアンダースコア_のみで、32文字以内で入力してください"
    end
    print "アカウント名> "
  end
  
  # Enter password
  puts "パスワードを入力してください\n"
  print "パスワード> "
  while (input = gets)
    input.strip!
    if (input.length >= 4 and input.length <= 16 and input != $account_name) then
      $account_password = input
      puts
      break
    else
      puts "！パスワードは4～16byte以内で、アカウント名と別の文字列を入力してください"
    end
    print "パスワード> "
  end
  
  # Save account to config
  $config['account']['name'] = $account_name
  $config['account']['password'] = $account_password
  save_config($config_file, $config)
  
  puts "アカウント情報を設定ファイルに保存しました。\n\n"
  puts "引き続き、対戦結果の報告をします...\n\n"
end
def doNewAccountSetup()
  puts "Can't find a valid account from config..."
  puts "Is the first time to use Tensokukan Net?"
  puts "★#{$variables['WEB_SERVICE_NAME']} アカウント設定（初回実行時）\n"  
  puts "#{$variables['WEB_SERVICE_NAME']} をはじめてご利用の場合、「1」をいれて Enter キーを押してください。"  
  puts "すでに緋行跡報告ツール等でアカウント登録済みの場合、「2」をいれて Enter キーを押してください。\n"  
  puts
  print "> "
  
  while (input = gets)
    input.strip!
    if input == "1"
      $is_new_account = true
      puts
      break
    elsif input == "2"
      $is_new_account = false
      puts
      break
    end
    
    puts "\nInvalid option.\n"
    puts "#{$variables['WEB_SERVICE_NAME']} をはじめてご利用の場合、「1」をいれて Enter キーを押してください。"  
    puts "すでに緋行跡報告ツール等で #{$variables['WEB_SERVICE_NAME']} アカウントを登録済みの場合、「2」をいれて Enter キーを押してください。\n"  
    puts
    print "> "
  end
  
  if $is_new_account
    doAccountSignUp()
  else
    doAccountLogin()
  end
  
  saveConfigFile()
end
def detectUploadAllMode()
  # If upload all mode is false
  unless $is_all_report then
    puts "★登録済みの最終対戦時刻を取得"
    puts "GET http://#{$SERVER_LAST_TRACK_RECORD_HOST}#{$SERVER_LAST_TRACK_RECORD_PATH}?$game_id=#{$game_id}&$account_name=#{$account_name}"
  
    http = Net::HTTP.new($SERVER_LAST_TRACK_RECORD_HOST, 80)
    $response = nil
    http.start do |s|
      $response = s.get("#{$SERVER_LAST_TRACK_RECORD_PATH}?game_id=#{$game_id}&account_name=#{$account_name}", $HTTP_REQUEST_HEADER)
    end
    printHTTPcode($response)
    
    if $response.code == '200' or $response.code == '204' then
      if ($response.body and $response.body != '') then
        $last_report_time = Time.parse($response.body)
        puts "サーバー登録済みの最終対戦時刻：#{$last_report_time.strftime('%Y/%m/%d %H:%M:%S')}"
      else
        $last_report_time = Time.at(0)
        puts "サーバーには対戦結果未登録です"
      end
    else
      raise "最終対戦時刻の取得時にサーバーエラーが発生しました。処理を中断します。"
    end
    
  else
    # If upload all mode is true
    puts "★全件報告モードです。サーバーからの登録済み最終対戦時刻の取得をスキップします。"
    $last_report_time = Time.at(0)
    end
end
def readDatafromDb()
  # Get the match results from database
  db_files = Dir::glob(NKF.nkf('-Wsxm0 --cp932', $db_file_path))

  if db_files.length > 0
    $trackrecord, $is_read_trackrecord_warning = read_trackrecord(db_files, $last_report_time + 1)
    $is_warning_exist = true if $is_read_trackrecord_warning
  else
    raise <<-MSG
#{$config_file} に設定された#{$RECORD_SW_NAME}データベースファイルが見つかりません。
・#{$PROGRAM_NAME}のインストール場所が正しいかどうか、確認してください
　デフォルト設定の場合、#{$RECORD_SW_NAME}フォルダに、#{$PROGRAM_NAME}をフォルダごとおいてください。
・#{$config_file} を変更した場合、設定が正しいかどうか、確認してください
    MSG
  end
  
  puts "★対戦結果送信"
  puts ("#{$RECORD_SW_NAME}の記録から、" + $last_report_time.strftime('%Y/%m/%d %H:%M:%S') + " 以降の対戦結果を報告します。")
  puts
end
def doUploadData()
  ## The uploading process
  
  # Don't upload if queue is empty
  if $trackrecord.length == 0 then
    puts "報告対象データはありませんでした。"
  else
    # Split the match results and send to server
    0.step($trackrecord.length, $TRACKRECORD_POST_SIZE) do |start_row_num|
      end_row_num = [start_row_num + $TRACKRECORD_POST_SIZE - 1, $trackrecord.length - 1].min
      $response = nil # サーバーからのレスポンスデータ
      
      puts "#{$trackrecord.length}件中の#{start_row_num + 1}件目～#{end_row_num + 1}件目を送信しています#{$is_force_insert ? "（強制インサートモード）" : ""}...\n"
      
      # Generate XML to upload
      trackrecord_xml_string = trackrecord2xml_string($game_id, $account_name, $account_password, $trackrecord[start_row_num..end_row_num], $is_force_insert)
      File.open('./last_report_trackrecord.xml', 'w') do |w|
        w.puts trackrecord_xml_string
      end

      # And then send to server
      http = Net::HTTP.new($SERVER_TRACK_RECORD_HOST, 80)
      http.start do |s|
        $response = s.post($SERVER_TRACK_RECORD_PATH, trackrecord_xml_string, $HTTP_REQUEST_HEADER)
      end
      printHTTPcode($response)
      
      # Display upload result from server
      puts "サーバーからのお返事"
      $response.body.each_line do |line|
        puts "> #{line}"
      end
      puts
      
      if $response.code == '200' then
        sleep 1
        # Meaning unknown code, keep original comments
        # 特に表示しない
      else
        if $response.body.index($PLEASE_RETRY_FORCE_INSERT)
          puts "強制インサートモードで報告しなおします。1秒後に報告再開...\n\n"
          sleep 1
          $is_force_insert = true
          redo
        else
          raise "報告時にサーバー側でエラーが発生しました。処理を中断します。"
        end
      end
    end
  end
end
def printExitMessage()
  if $is_warning_exist then
    puts "報告処理は正常に終了しましたが、警告メッセージがあります。"
    puts "出力結果をご確認ください。"
    puts
    puts "Enter キーを押すと、処理を終了します。"
    exit if gets
    puts
  else
    puts "報告処理が正常に終了しました。"
  end
end

# Start
begin
  parseLaunchArguments()
  importConfigToVariables()
  doDebugAction()
  detectExistAccount()

  if $updateCheck
    doUpdateCheck()
  end
  
  if $is_account_register_finish != true
    doNewAccountSetup()
  end
    
  # Get the account-based latest upload time from server
  $last_report_time = nil
  $response = nil
  detectUploadAllMode()
  readDatafromDb()
  doUploadData()

  # Exit message output
  printExitMessage()

### Overall error handling ###
rescue => ex
  if $config && $config['account'] then
    $config['account']['name']     = '<secret>' if $config['account']['name']
    $config['account']['password'] = '<secret>' if $config['account']['password']
  end
  
  puts 
  puts "処理中にエラーが発生しました。処理を中断します。\n"
  puts 
  puts '### エラー詳細ここから ###'
  puts
  puts ex.to_s
  puts
  puts ex.backtrace.join("\n")
  puts ($config ? $config.to_yaml : "config が設定されていません。")
  if $response then
    puts
    puts "<サーバーからの最後のメッセージ>"
    puts "HTTP status code : #{$response.code}"
    puts $response.body
  end
  puts
  puts '### エラー詳細ここまで ###'
  
  File.open($ERROR_LOG_PATH, 'w') do |log|
    log.puts "#{Time.now.strftime('%Y/%m/%d %H:%M:%S')} #{File::basename(__FILE__)} #{$PROGRAM_VERSION}" 
    log.puts ex.to_s
    log.puts ex.backtrace.join("\n")
    log.puts $config ? $config.to_yaml : "config が設定されていません。"
    if $response then
      log.puts "<サーバーからの最後のメッセージ>"
      log.puts "HTTP status code : #{$response.code}"
      log.puts $response.body
    end
    log.puts '********'
  end
  
  puts
  puts "上記のエラー内容を #{$ERROR_LOG_PATH} に書き出しました。"
  puts
  
  puts "Enter キーを押すと、処理を終了します。"
  exit if gets
    end