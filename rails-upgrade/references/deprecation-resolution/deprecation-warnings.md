# Deprecation Warnings: Where They Surface & How to Configure Rails

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

This reference covers *where* deprecation warnings appear and *how to configure Rails* to report them. For the resolution workflow, see `workflows/deprecation-resolution-workflow.md`. For fix strategies (regex, synvert, backward-compat), see `deprecation-strategies.md`.

---

## Overview

Deprecation warnings announce that a feature (method, class, API) will be removed in a future Rails version. Features are deprecated rather than immediately removed to:

- Provide backward compatibility
- Give developers time to update
- Allow gradual migration to new patterns

All Rails deprecation warnings start with `DEPRECATION WARNING:`.

---

## Where Deprecations Surface

### Test Suite Logs

```bash
bundle exec rspec 2>&1 | tee test_output.log
grep "DEPRECATION WARNING" test_output.log
```

Or directly from the Rails test log:

```bash
grep "DEPRECATION WARNING" log/test.log
```

### CI Services

Most CI (GitHub Actions, CircleCI, Travis) preserves full test output. Search the build log for `DEPRECATION WARNING`.

### Production

Production warnings are best captured via an error tracker. Configure Rails to notify, then subscribe:

```ruby
# config/environments/production.rb
config.active_support.deprecation = :notify
```

```ruby
# config/initializers/deprecation_warnings.rb
ActiveSupport::Notifications.subscribe('deprecation.rails') do |name, start, finish, id, payload|
  # Honeybadger
  Honeybadger.notify(
    error_class: "DeprecationWarning",
    error_message: payload[:message],
    backtrace: payload[:callstack]
  )

  # Or Sentry
  # Sentry.capture_message(payload[:message], level: :warning, backtrace: payload[:callstack])

  # Or Airbrake
  # Airbrake.notify(error_class: "DeprecationWarning", error_message: payload[:message], backtrace: payload[:callstack])
end
```

See the [ActiveSupport Instrumentation Guide](https://guides.rubyonrails.org/active_support_instrumentation.html#subscribing-to-an-event) for details.

Alternative, log to `production.log`:

```ruby
config.active_support.deprecation = :log
```

Noisy on high-traffic apps, prefer `:notify` + a tracker.

---

## Configuration Options

| Setting | Behavior |
|---------|----------|
| `:raise` | Raise an exception (stops execution) |
| `:log` | Log to Rails logger |
| `:notify` | Send to `ActiveSupport::Notifications` |
| `:silence` | Ignore (not recommended, hides signal) |
| `:stderr` | Print to stderr |
| `:report` | Report via error reporter (Rails 7.1+) |

### Recommended per environment

```ruby
# config/environments/development.rb
config.active_support.deprecation = :raise

# config/environments/test.rb
config.active_support.deprecation = :raise

# config/environments/production.rb
config.active_support.deprecation = :notify
```

**Upgrade-time caveat:** if the suite currently silences deprecations, flip to `:stderr` or `:log` (not `:raise`) while collecting the baseline in Step 1. `:raise` halts the suite on the first warning and hides the rest of the list. Switch to `:raise` after the backlog is cleared to prevent regressions.

---

## Rails 6.1+ Disallowed Deprecations

Rails 6.1 introduced `disallowed_warnings`, fix-then-lock so a pattern cannot reappear:

```ruby
# config/environments/test.rb

ActiveSupport::Deprecation.disallowed_behavior = [:raise]

ActiveSupport::Deprecation.disallowed_warnings = [
  # String match
  "update_attributes",

  # Symbol match
  :update_attributes,

  # Regex match
  /(update_attributes)!?/,

  # Multiple patterns
  "before_filter",
  "after_filter",
]
```

Behavior:
- **Allowed** deprecations, logged normally (warning level)
- **Disallowed** deprecations, raise in dev/test, error-level in production

Intended use: after fixing a deprecation, add it to `disallowed_warnings`; any reintroduction fails tests. The resolution workflow uses this as its regression-prevention step.

---

## Common Deprecation Patterns by Rails Version

### Rails 5.0 → 5.1
- `render :text` → `render :plain`
- `redirect_to :back` → `redirect_back`

### Rails 5.1 → 5.2
- `secrets.yml` → `credentials.yml.enc`
- `config.active_record.belongs_to_required_by_default`

### Rails 5.2 → 6.0
- `update_attributes` → `update`
- Classic autoloader → Zeitwerk

### Rails 6.0 → 6.1
- `Rails.application.secrets` → `Rails.application.credentials`

### Rails 6.1 → 7.0
- `to_s(:format)` → `to_fs(:format)`
- Turbolinks → Turbo

### Rails 7.0 → 7.1
- `before_action` callback order changes
- `config.cache_classes` → `config.enable_reloading`

### Rails 7.1 → 7.2
- `show_exceptions` boolean → symbol
- `params == hash` → `params.to_h == hash`

---

## Resources

- [Rails Deprecation Behavior](https://guides.rubyonrails.org/configuring.html#config-active-support-deprecation)
- [ActiveSupport Instrumentation](https://guides.rubyonrails.org/active_support_instrumentation.html)
- [Rubocop](https://github.com/rubocop-hq/rubocop) (see `deprecation-strategies.md` for custom-cop regression prevention)
