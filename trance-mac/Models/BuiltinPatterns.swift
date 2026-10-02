import Foundation

public enum BuiltinPatterns {
    public static let sources: [String: String] = [
        "accelerate": #"""
pattern accelerate for 2048f {
  every ramp 56f -> 12f steps 140 ease early -> cut {
    image alternate chance 0.5 zoom [0.4 * accelerate.progress + 0.1 * this.progress] origin (curve 0 -> 0.4 over accelerate) anim every 4th
    word primary show 0..0.25 chance 0.5
  }
  spiral speed (curve 1 -> 4 over accelerate)
}
"""#,
        "slow_flash": #"""
pattern slow_flash for 1536f loop 2 seq {
  pattern slow for 1024f {
    every 64f { image primary zoom (curve 0 -> 0.5) anim every 2nd }
    every 64f { caption primary }
    spiral speed 2
  }
  pattern fast for 512f {
    every 8f  { image secondary zoom (curve 0 -> 0.8 over fast) }
    every 16f { word secondary }
    spiral speed 4
  }
}
"""#,
        "sub_text": #"""
pattern sub_text for 1024f {
  every 64f { image runtime zoom (curve 0 -> 0.375) anim every 3rd }
  every 32f { subtext secondary }
  spiral speed 4
}
"""#,
        "flash_text": #"""
pattern flash_text for 1024f {
  pattern life for 128f loop 8 {
    every 64f -> beat {
      copy cur -> prev
      draw prev          zoom (curve 0.4 -> 0.8)
      image secondary -> cur fade in zoom (curve 0 -> 0.4)
    }
    every 64f { word secondary }
  }
  every 32f { caption primary }
  spiral speed 2
}
"""#,
        "parallel": #"""
pattern simple for 2048f {
  every 64f { image runtime zoom (curve 0 -> 0.5) anim every 3rd }
  every 32f { caption primary }
  spiral speed 3
}
"""#,
        "super_parallel": #"""
pattern super_parallel for 1152f {
  every 96f            { image primary   -> a zoom (curve 0 -> 0.875) anim every 2nd }
  every 96f offset 32f { image primary   -> b alpha 0.5 zoom (curve 0 -> 0.875) }
  every 96f offset 64f { image secondary -> c alpha 0.33 zoom (curve 0 -> 0.875) }
  every 32f { word runtime }
  spiral speed 3
}
"""#,
        "animation": #"""
pattern animation for 1024f {
  every 64f { image runtime zoom (curve 0 -> 0.625) anim }
  every 64f offset 48f { image secondary -> still env in 8f hold 16f out 8f zoom (curve 0.5 -> 0.625) }
  every 32f { caption runtime }
  spiral speed 3
}
"""#,
        "super_fast": #"""
pattern super_fast for 2048f {
  burst -> rapid period 8f chance 1/12 cooldown 64f duration 64f..128f {
    base {
      every 8f { image runtime zoom (curve 0.0625 -> 0.1875) }
    }
    burst { image runtime zoom (curve 0.1 -> 0.7) anim }
  }
  every 8f { word primary chance 0.25 }
  spiral speed 3
}
"""#,
    ]
}
