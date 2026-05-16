require "test_helper"

class RetiredHandleTest < ActiveSupport::TestCase
  setup do
    @server = create(:server)
  end

  test "reserved? returns true within the 30-day window" do
    RetiredHandle.create!(server: @server, handle_lower: "stark", freed_at: 5.days.ago)
    assert RetiredHandle.reserved?(server_id: @server.id, handle: "Stark")
  end

  test "reserved? returns false after the window expires" do
    RetiredHandle.create!(server: @server, handle_lower: "stark", freed_at: 31.days.ago)
    refute RetiredHandle.reserved?(server_id: @server.id, handle: "Stark")
  end

  test "reserved? returns false for nil handle" do
    refute RetiredHandle.reserved?(server_id: @server.id, handle: nil)
  end
end
