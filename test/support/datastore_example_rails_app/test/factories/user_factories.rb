FactoryBot.define do
  factory :user do
    name              { 'A Test User' }
    email             { Faker::Internet.email }
    role              { 1 }
  end
end
