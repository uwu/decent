require "./reactivity.rb"
require "./terminal_renderer.rb"

module Decent
  class App
    include Decent

    def initialize(renderer = nil, &tui)
      @renderer = renderer || TerminalRenderer.new(STDOUT)

      @tree = { type: "root", children: [] }
      @tree[:parent] = @tree

      @current_node = @tree

      instance_eval(&tui)
    end

    def ref(initial)
      Ref.new initial
    end
    
    def derived(&watcher)
      sig = ref nil
  
      effect do
        sig.value = watcher.call
      end
  
      sig
    end

    # todo: add code to bind this to the current node
    def effect(dependencies = nil, &watcher)
      return Effect.new(dependencies, &watcher)
    end

    def element(name, properties = {}, &children)
      subscriptions = []
      node = { type: name, properties: properties, children: [], parent: @current_node, subscriptions: subscriptions }

      properties.each do |key, prop|
        if prop.is_a?(Ref)
          properties[key] = prop.value

          render_effect = effect [prop] do
            properties[key] = prop.value
            render
          end

          subscriptions << render_effect
        end
      end

      @current_node[:children] << node
      @current_node = node
      children&.call
      @current_node = @current_node[:parent]

      node
    end

    # this entire thing is currently fucked because we do not unsubscribe from the children's effects
    # theoretically speaking the solution to this problem is to push every subscription to the current node's subscriptions list
    # then upon rerendering we just traverse the tree and unsubscribe
    def show(args, &children)
      cond = args[:if]

      # this has cond: as a property to trigger a rerender when the value changes
      node = element("show", { cond: cond })

      should_show = false

      effect [cond] do
        if should_show != cond.value
          should_show = cond.value

          if cond.value
            @current_node = node

            children&.call
          else
            node[:children] = []
          end
        end
      end
    end

    # this currently triggers a render twice upon initialization.
    # this is because we do not have explicit dependency arrays and call `render` inside of the effect body.
    # TODO: make this not shit
    def each(args, &child)
      of = args[:of]
      node = element("each")

      effect do
        node[:children] = []

        of.value.each_with_index do |item, index|
          @current_node = node

          child.call item, index
        end

        render
      end
    end

    def box(width: "auto", height: "auto", &children)
      element("box", { width: width, height: height,  }, &children)
    end

    def text(text)
      element("text", { content: text })
    end

    def render
      @renderer.clear
      # these go in the order of starting coordinates (x, y), then the max amount rows and cols
      @bounds = [[0, 0], @renderer.size]

      stack = [@tree]

      until stack.length == 0
        node = stack.pop

        # todo: this is a hack until i get rendering to work in the correct order
        stack.concat node[:children].reverse

        properties = node[:properties]


        # todo: nothing here actually resets the bounds when we leave the component. not good.
        case node[:type]
        when "text"
          # text wrapping stuff :)
          @renderer.draw properties[:content].chars.each_slice(@bounds[1][0]).map(&:join).join("\n"), @bounds[0][0], @bounds[0][1]

          # todo: remove this shit later, layouting should be handled by stacks and flows, not by the components themselves
          # also, the .length + 1 shit is just to add a space, not *really* necessary
          @bounds[0][0] += properties[:content].length + 1
        when "box"
          box = ""

          width = properties[:width] == "auto" ? @bounds[1][0] : properties[:width]
          height = properties[:height] == "auto" ? @bounds[1][1] : properties[:height]

          box << "┌#{'─' * (width - 2)}┐\n"
          box << "│#{' ' * (width - 2)}│\n" * (height - 2)
          box << "└#{'─' * (width - 2)}┘"

          @renderer.draw box, @bounds[0][0], @bounds[0][1]

          @bounds[0][0] += 1
          @bounds[0][1] += 1
          @bounds[1][0] = width - 2
          @bounds[1][1] = height - 2
        end
      end

      @renderer.render
    end

    def run
      begin
        @renderer.setup
        render
        loop {}
      ensure
        @renderer.cleanup
      end
    end
  end
end
