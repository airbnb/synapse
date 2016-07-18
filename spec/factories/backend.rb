FactoryGirl.define do
  factory :backend, :class => Hash do
    sequence(:name) { |n| "server#{n}" }
    sequence(:host) { |n| "hostname#{n}" }
    sequence(:port)

    labels  {}

    # needed to build hashes instead of classes
    initialize_with { attributes }

    # convert keys to strings, since backends always have string keys
    after(:build) do |backend|
      backend.keys.each do |k|
        backend[k.to_s] = backend[k]
        backend.delete(k)
      end
    end
  end
end
