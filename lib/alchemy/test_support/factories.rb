require 'factory_girl'

FactoryGirl.define do

  factory :user, class: 'DummyUser' do
    sequence(:email) { |n| "john.#{n}@doe.com" }
    password 's3cr3t'

    factory :admin_user do
      alchemy_roles ['admin']
    end

    factory :member_user do
      alchemy_roles ['member']
    end

    factory :author_user do
      alchemy_roles ['author']
    end

    factory :editor_user do
      alchemy_roles ['editor']
    end
  end

  factory :language, :class => 'Alchemy::Language' do
    name 'Deutsch'
    code 'de'
    default true
    frontpage_name 'Intro'
    page_layout { Alchemy::Config.get(:default_language)['page_layout'] }
    public true
    site { Alchemy::Site.first }

    factory :klingonian do
      name 'Klingonian'
      code 'kl'
      frontpage_name 'Tuq'
      default false
    end

    factory :english do
      name 'English'
      code 'en'
      frontpage_name 'Intro'
      default false
    end
  end

  factory :page, :class => 'Alchemy::Page' do
    language { Alchemy::Language.default }
    sequence(:name) { |n| "A Page #{n}" }
    page_layout "standard"

    # This speeds up creating of pages dramatically. Pass :do_not_autogenerate => false to generate elements
    do_not_autogenerate true

    factory :public_page do
      sequence(:name) { |n| "A Public Page #{n}" }
      public true
    end

    factory :systempage do
      name "Systempage"
      page_layout nil
      language nil
    end

    factory :restricted_page do
      name "Restricted page"
      restricted true
    end
  end

  factory :cell, class: 'Alchemy::Cell' do
    page
    name "a_cell"
  end

  factory :element, :class => 'Alchemy::Element' do
    name 'article'
    create_contents_after_create false

    factory :unique_element do
      unique true
      name 'header'
    end
  end

  factory :picture, :class => 'Alchemy::Picture' do
    image_file File.new(File.expand_path('../../../../spec/fixtures/image.png', __FILE__))
    name 'image'
    image_file_name 'image.png'
    upload_hash Time.now.hash
  end

  factory :content, :class => 'Alchemy::Content' do
    name "text"
    essence_type "Alchemy::EssenceText"
    association :essence, :factory => :essence_text
  end

  factory :essence_text, :class => 'Alchemy::EssenceText' do
    body ''
  end

  factory :essence_picture, :class => 'Alchemy::EssencePicture' do
    picture
  end

  factory :essence_file, :class => 'Alchemy::EssenceFile' do
    attachment
  end

  factory :attachment, :class => 'Alchemy::Attachment' do
    file File.new(File.expand_path('../../../../spec/fixtures/image.png', __FILE__))
    name 'image'
    file_name 'image.png'
  end

  factory :event do
    name 'My Event'
    hidden_name 'not shown'
    starts_at DateTime.new(2012, 03, 02, 8, 15)
    ends_at DateTime.new(2012, 03, 02, 19, 30)
    lunch_starts_at DateTime.new(2012, 03, 02, 12, 15)
    lunch_ends_at DateTime.new(2012, 03, 02, 13, 45)
    description "something\nfancy"
    published false
    entrance_fee 12.3
  end

  factory :site, class: 'Alchemy::Site' do
    name 'A Site'
    host 'domain.com'
  end
end
