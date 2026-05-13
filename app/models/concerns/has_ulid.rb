module HasUlid
  extend ActiveSupport::Concern

  included do
    before_create :generate_ulid
  end

  private

  def generate_ulid
    self.id ||= ULID.generate
  end
end
