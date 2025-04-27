class Customer < ApplicationRecord
  has_many :svrs
  
  validates :name, presence: true
end
