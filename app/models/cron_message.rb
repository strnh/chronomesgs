class CronMessage < ApplicationRecord
  belongs_to :cron
  
  validates :cron_id, presence: true
  
  scope :alerts, -> { where(alert: true) }
  scope :recent, -> { where("sendtime > ?", 7.days.ago) }
  
  def message_summary
    if alert?
      "ALERT: #{last_error}"
    else
      "OK: #{sender} -> #{receiver} at #{sendtime.strftime('%Y-%m-%d %H:%M')}"
    end
  end
end
