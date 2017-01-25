FactoryGirl.define do
  factory :mock_model do
    sequence :name do |n|
      "Test Mock Model #{n}"
    end
  end
end
