require "test_helper"

module Titles
  class RenderTest < ActiveSupport::TestCase
    setup do
      @profile = create(:player_profile)
    end

    test "returns nil with no titles" do
      assert_nil Render.call(@profile)
    end

    test "renders single-win title" do
      world = create(:world, :active, server: @profile.server, name: "Aldermarch")
      PlayerTitle.create!(player_profile: @profile, world: world, awarded_at: Time.current)
      assert_equal "[Champion of Aldermarch]", Render.call(@profile)
    end

    test "appends ×N for repeat wins on same world name" do
      w1 = create(:world, :active, server: @profile.server, name: "Aldermarch")
      w2 = create(:world, :active, server: @profile.server, name: "Aldermarch")
      w3 = create(:world, :active, server: @profile.server, name: "Aldermarch")
      PlayerTitle.create!(player_profile: @profile, world: w1, awarded_at: 2.days.ago)
      PlayerTitle.create!(player_profile: @profile, world: w2, awarded_at: 1.day.ago)
      PlayerTitle.create!(player_profile: @profile, world: w3, awarded_at: Time.current)
      assert_equal "[Champion of Aldermarch ×3]", Render.call(@profile)
    end

    test "picks most recent world across different names" do
      w1 = create(:world, :active, server: @profile.server, name: "Aldermarch")
      w2 = create(:world, :active, server: @profile.server, name: "Brimwood")
      PlayerTitle.create!(player_profile: @profile, world: w1, awarded_at: 2.days.ago)
      PlayerTitle.create!(player_profile: @profile, world: w2, awarded_at: 1.day.ago)
      assert_equal "[Champion of Brimwood]", Render.call(@profile)
    end
  end
end
