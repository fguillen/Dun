require "test_helper"

class RoundArchiveTest < ActiveSupport::TestCase
  setup do
    @world = create(:world, :active)
  end

  test "is valid with frozen_state defaulting to {}" do
    archive = RoundArchive.create!(world: @world, ended_at: Time.current)
    assert_equal({}, archive.frozen_state)
  end

  test "enforces world uniqueness" do
    RoundArchive.create!(world: @world, ended_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) do
      RoundArchive.create!(world: @world, ended_at: Time.current)
    end
  end
end
