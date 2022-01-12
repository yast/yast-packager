module Yast
  # A wrapper for SlideShowCallbacks:: module,
  # required for removing the cyclic import dependency
  # between SlideShowCallbacks.ycp and SlideShow.ycp
  class WrapperSlideshowCallbacksClient < Client
    def main
      @func = Convert.to_string(WFM.Args(0))
      @param = []

      # get parameters if available
      @param = Convert.to_list(WFM.Args(1)) if Ops.greater_or_equal(Builtins.size(WFM.Args), 2)

      @ret = nil

      Builtins.y2milestone(
        "SlideShowCallbacks:: wrapper: func: %1, args: %2",
        @func,
        @param
      )

      Yast.import "SlideShowCallbacks"

      # call the required function
      case @func
      when "InstallSlideShowCallbacks"
        @ret = SlideShowCallbacks.InstallSlideShowCallbacks
      when "RemoveSlideShowCallbacks"
        @ret = SlideShowCallbacks.RemoveSlideShowCallbacks
      else
        # the required function is not known
        Builtins.y2error("unknown function: %1", @func)
      end

      Builtins.y2milestone("SlideShowCallbacks wrapper: result: %1", @ret)

      deep_copy(@ret)
    end
  end
end

Yast::WrapperSlideshowCallbacksClient.new.main
