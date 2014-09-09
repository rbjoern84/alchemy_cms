module Alchemy
  module Page::PageNaming

    extend ActiveSupport::Concern
    include NameConversions
    RESERVED_URLNAMES = %w(admin messages new)

    included do
      before_validation :set_urlname,
        unless: -> { name.blank? }

      validates :name,
        presence: true

      validates :urlname,
        uniqueness: {
          scope: [:language_id, :layoutpage],
          if: 'urlname.present?'
        },
        exclusion: {
          in: RESERVED_URLNAMES
        },
        length: {
          minimum: 3,
          if: 'urlname.present?'
        }

      before_save :set_title,
        if: -> { title.blank? }

      after_update :update_children_urlnames,
        if: -> { children.any? && urlname_changed? }
    end

    # Returns always the last part of a urlname path
    def slug
      urlname.to_s.split('/').last
    end

    # Updates the urlname column directly in the database
    # NOTE: Does not call any callbacks!
    def update_urlname!
      update_column(:urlname, nested_urlname)
    end

    private

    # Sets the urlname attribute to a url friendly slug.
    # NOTE: Does not save
    def set_urlname
      write_attribute(:urlname, nested_urlname)
    end

    # Returns the urlname to a url friendly slug.
    #
    def nested_urlname
      url_name = [
        parent_urlname,
        convert_url_name(urlname.blank? ? name : slug)
      ].compact.join('/')
    end

    # Calls update_urlname! of all children
    def update_children_urlnames
      children.map(&:update_urlname!)
    end

    def set_title
      write_attribute :title, name
    end

    # Converts the given name into an url friendly string.
    #
    # Names shorter than 3 will be filled up with dashes,
    # so it does not collidate with the language code.
    #
    def convert_url_name(name)
      url_name = convert_to_urlname(name)
      if url_name.length < 3
        ('-' * (3 - url_name.length)) + url_name
      else
        url_name
      end
    end
  end
end
