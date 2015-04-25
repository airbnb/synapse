class Tree
  include Comparable
  def initialize(value, children)
    @value = value
    @children = children
  end
  def get_value
    @value
  end
  def <=>(anOther)
    @value <=> anOther.get_value
  end
  def get_children()
    @children
  end
  def getChild(value)
    selected = @children.select{ |child|
      child.get_value == value
    }
    return selected[0] unless selected.nil?
  end
  def add_child(child)
    existing = getChild(child.get_value)
    if existing.nil? && child.is_a?(Tree)
      @children = @children.push(child)
      existing = child
    end
    existing
  end
  def add_path(path)
    if path.is_a?(Array) && path.size > 0
      child = add_child(Tree.new(path[0], []))
      child.add_path(path.drop(1))
    end
  end
  def find(path)
    if path.is_a?(Array)
      if path.size == 0
        return self
      else
        child = getChild(path[0])
        return child.find(path.drop(1)) unless child.nil?
      end
    end
    return nil
  end
  def to_s
    "<#{@value}>: #{@children}"
  end
  def inspect
    to_s
  end
end