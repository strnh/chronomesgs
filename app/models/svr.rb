class Svr < ApplicationRecord
  has_many :crons, foreign_key: :svr_id, primary_key: :id
  belongs_to :customer, optional: true
  
  validates :name, presence: true, uniqueness: { scope: :customer_id }
  
  def svr_status
    # サーバー状態を返すヘルパーメソッド
    if last_update.present? && last_update > 24.hours.ago
      "active"
    else
      "inactive"
    end
  end
end
