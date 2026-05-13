require "test_helper"

class DelaunayTest < ActiveSupport::TestCase
  test "triangulates a simple square into two triangles" do
    points = [
      { x: 0.0, y: 0.0 },
      { x: 1.0, y: 0.0 },
      { x: 1.0, y: 1.0 },
      { x: 0.0, y: 1.0 }
    ]
    edges = Dun::Delaunay.edges_for(points)

    # 4 corner edges + 1 diagonal = 5 edges
    assert_equal 5, edges.size
    # Every corner participates in at least 2 edges
    counts = Array.new(4, 0)
    edges.each { |i, j| counts[i] += 1; counts[j] += 1 }
    assert counts.all? { |c| c >= 2 }, "every corner should connect to >=2 others"
  end

  test "edges are deduplicated (i, j with i < j)" do
    points = (0...5).map { |i| { x: i * 0.2, y: rand } }
    edges = Dun::Delaunay.edges_for(points)
    assert edges.all? { |i, j| i < j }, "edges must be sorted (i < j)"
    assert_equal edges.uniq.size, edges.size, "edges must be unique"
  end

  test "all points end up in some edge for n>=3" do
    rng = Random.new(42)
    points = Array.new(20) { { x: rng.rand, y: rng.rand } }
    edges = Dun::Delaunay.edges_for(points)
    touched = edges.flatten.uniq.sort
    assert_equal (0...20).to_a, touched
  end
end
