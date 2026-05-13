module Dun
  module Delaunay
    Point = Struct.new(:x, :y, :index, keyword_init: true)
    Triangle = Struct.new(:a, :b, :c, keyword_init: true)

    def self.edges_for(points)
      pts = points.each_with_index.map { |p, i| Point.new(x: p[:x].to_f, y: p[:y].to_f, index: i) }
      tris = triangulate(pts)
      edge_set = {}
      tris.each do |t|
        [ [ t.a, t.b ], [ t.b, t.c ], [ t.c, t.a ] ].each do |a, b|
          key = [ a.index, b.index ].sort
          edge_set[key] = true
        end
      end
      edge_set.keys
    end

    def self.triangulate(pts)
      min_x, max_x = pts.map(&:x).minmax
      min_y, max_y = pts.map(&:y).minmax
      dx = (max_x - min_x).nonzero? || 1.0
      dy = (max_y - min_y).nonzero? || 1.0
      delta = [ dx, dy ].max * 20.0
      cx = (min_x + max_x) / 2.0
      cy = (min_y + max_y) / 2.0
      sa = Point.new(x: cx - 2 * delta, y: cy - delta,     index: -1)
      sb = Point.new(x: cx + 2 * delta, y: cy - delta,     index: -2)
      sc = Point.new(x: cx,             y: cy + 2 * delta, index: -3)

      triangles = [ Triangle.new(a: sa, b: sb, c: sc) ]

      pts.each do |p|
        bad = triangles.select { |t| in_circumcircle?(p, t) }
        edge_count = Hash.new(0)
        bad.each do |t|
          triangle_edges(t).each do |a, b|
            edge_count[[ a.index, b.index ].sort] += 1
          end
        end
        boundary = []
        bad.each do |t|
          triangle_edges(t).each do |a, b|
            boundary << [ a, b ] if edge_count[[ a.index, b.index ].sort] == 1
          end
        end
        triangles -= bad
        boundary.each { |a, b| triangles << Triangle.new(a: a, b: b, c: p) }
      end

      triangles.reject { |t| [ t.a.index, t.b.index, t.c.index ].any? { |i| i < 0 } }
    end

    def self.triangle_edges(t)
      [ [ t.a, t.b ], [ t.b, t.c ], [ t.c, t.a ] ]
    end

    def self.in_circumcircle?(p, t)
      a = t.a
      b = t.b
      c = t.c
      ax = a.x - p.x; ay = a.y - p.y
      bx = b.x - p.x; by = b.y - p.y
      cx = c.x - p.x; cy = c.y - p.y
      det = (ax * ax + ay * ay) * (bx * cy - by * cx) \
          - (bx * bx + by * by) * (ax * cy - ay * cx) \
          + (cx * cx + cy * cy) * (ax * by - ay * bx)
      orient = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
      orient.positive? ? det > 0 : det < 0
    end
  end
end
