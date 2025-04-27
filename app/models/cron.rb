class Cron < ApplicationRecord
  belongs_to :svr, foreign_key: :svr_id, primary_key: :id
  has_many :cron_messages
  
  validates :name, :svr_id, :command, presence: true
  
  scope :active, -> { where(active: true, deleted: false, valid: true) }
  
  # 期間グループに応じたScopeを定義
  scope :daily, -> { where(period_group: "daily") }
  scope :weekly, -> { where(period_group: "weekly") }
  scope :monthly, -> { where(period_group: "monthly") }
  
  def expected_next_run
    # 次回実行予定時刻を計算するロジック
    case period_group
    when "daily"
      Time.current.beginning_of_day + period_hour.hours + period_min.minutes
    when "weekly"
      day = Time.current.beginning_of_week + period_dweek.days
      day + period_hour.hours + period_min.minutes
    when "monthly"
      day = Time.current.beginning_of_month + (period_dmon - 1).days
      day + period_hour.hours + period_min.minutes
    else
      nil
    end
  end
  
  def check_missing_messages
    # 最後のメッセージを確認
    last_msg = cron_messages.order(sendtime: :desc).first
    
    # 許容時間を計算（期間グループによる）
    grace_period = case period_group
                   when "daily" then 1.hour
                   when "weekly" then 3.hours
                   when "monthly" then 6.hours
                   else 1.hour
                   end
    
    # 次回実行予定時刻 + 猶予期間を過ぎているかをチェック
    if last_msg.nil? || last_msg.sendtime < (expected_next_run - grace_period)
      create_alert_message
      true
    else
      false
    end
  end
  
  def create_alert_message
    # アラートメッセージを作成
    cron_messages.create(
      sendtime: Time.current,
      recvdate: Time.current,
      sender: "system",
      receiver: "admin",
      alert: true,
      last_error: "Expected cron execution message not received"
    )
  end
end
