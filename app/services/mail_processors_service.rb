#
# MailProcessorService の主な機能
#
#    初期化（initialize メソッド）:
#        mail_content パラメータで受け取った生のメールデータを保存し、parse_mail メソッドを使って解析します。
#        Mail クラス（Ruby の mail gem）を使ってメールをパースします。
#    メール処理（process メソッド）: これが主要なメソッドで、以下の処理を行います：
#        メールのヘッダー情報（差出人、宛先、件名、送信日時）を取得します。
#        メールの件名から正規表現を使ってcron情報を抽出します。
#            例えば [Cron <root@server1>: /backup.sh] という形式から：
#                cron_user = "root"
#                server_name = "server1"
#                command = "/backup.sh"
#        抽出したサーバー名から該当する Svr レコードをデータベースで検索します。
#        サーバーが見つかった場合、コマンドとユーザーの組み合わせからcronジョブを特定します。
#    既存のcronジョブの場合:
#        該当するcronが見つかった場合、そのcronに関連付いた新しい CronMessage を作成します。
#        メッセージには、送信時間、受信時間、送信者、受信者、アラート状態、エラーメッセージが含まれます。
#        メッセージの保存に成功したら成功ステータスと作成したメッセージを返します。
#    新規cronジョブの自動検出:
#        サーバーは見つかったが、該当するcronジョブがデータベースに存在しない場合、自動的に新しいcronレコードを作成します。
#        新しいcronにはデフォルト値として「日次」実行の設定を与え、メールの送信時刻から実行時間（時・分）を設定します。
#        作成したcronに紐づく新しいメッセージも同時に作成し、成功ステータスとメッセージ、および新規cron作成のフラグを返します。
#    エラー処理:
#        サーバーが見つからない場合やメール形式が不正な場合、適切なエラーメッセージを返します。
#    エラーメッセージ抽出（extract_error_message メソッド）:
#        メール本文から「error」「fail」「exception」などのキーワードを含む行を抽出します。
#        エラーメッセージが見つかった場合、データベースのフィールド長制限に合わせて切り詰めます（最大255文字）。

#このサービスの重要性

#    自動ログ収集:
#        cronジョブの実行結果メールを自動的に処理し、DBに保存します。
#        定型メールフォーマットを認識し、構造化データとして保存します。
#    自己学習的な設計:
#        未知のcronジョブからのメールも受信し、新規登録してトラッキングを始めます。
#        システムがメールから実行パターンを自動的に学習できます。
#    エラー検出:
#        メール本文からエラーメッセージを自動抽出し、問題を素早く特定できます。
i
# このサービスは、メール受信用APIエンドポイント（MailReceiverController）と連携して動作し、cronジョブの監視システムの中核となる機能を提供します。メールサーバーからこのAPIにcronメールを転送するよう設定することで、システム全体が機能します。
#
#
class MailProcessorService
  def initialize(mail_content)
    @mail_content = mail_content
    @parsed_mail = parse_mail(mail_content)
  end
  
  def process
    # メールヘッダー情報を取得
    from = @parsed_mail.from.first
    to = @parsed_mail.to.first
    subject = @parsed_mail.subject
    sent_date = @parsed_mail.date
    
    # subjectからcron情報を抽出 (例: [Cron <root@server1>: /backup.sh] のようなフォーマット)
    if subject =~ /\[Cron <(.+?)@(.+?)>: (.+?)\]/
      cron_user = $1
      server_name = $2
      command = $3
      
      # サーバー名からSvrレコードを探す
      svr = Svr.find_by(name: server_name) || Svr.find_by(fqdn: server_name)
      
      if svr
        # コマンドとユーザーからCronを検索
        cron = svr.crons.find_by(command: command, cron_user: cron_user)
        
        if cron
          # CronMessageを作成
          message = cron.cron_messages.new(
            sendtime: sent_date,
            recvdate: Time.current,
            sender: from,
            receiver: to,
            alert: false,
            last_error: extract_error_message(@parsed_mail.body.decoded)
          )
          
          if message.save
            { success: true, message: message }
          else
            { success: false, error: "Failed to save message: #{message.errors.full_messages.join(', ')}" }
          end
        else
          # 該当するCronが見つからない場合は新規作成
          new_cron = svr.crons.create(
            name: "Auto detected: #{command}",
            command: command,
            cron_user: cron_user,
            period_group: "daily", # デフォルト値
            period_hour: sent_date.hour,
            period_min: sent_date.min,
            active: true
          )
          
          message = new_cron.cron_messages.create(
            sendtime: sent_date,
            recvdate: Time.current,
            sender: from,
            receiver: to,
            alert: false,
            last_error: extract_error_message(@parsed_mail.body.decoded)
          )
          
          { success: true, message: message, new_cron: true }
        end
      else
        { success: false, error: "Server not found: #{server_name}" }
      end
    else
      { success: false, error: "Invalid cron mail format" }
    end
  end
  
  private
  
  def parse_mail(mail_content)
    Mail.new(mail_content)
  end
  
  def extract_error_message(body)
    # メール本文からエラーメッセージを抽出するロジック
    error_lines = body.split("\n").select { |line| line =~ /error|fail|exception/i }
    
    if error_lines.any?
      error_lines.join("\n")[0..255] # DBのstring型フィールドに収まる長さに切り詰め
    else
      ""
    end
  end
end

