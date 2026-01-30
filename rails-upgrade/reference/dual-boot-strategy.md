# Dual-Boot Strategy for Rails Upgrades

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

---

## Overview

Dual-booting is a powerful strategy that allows you to run your application with two different Rails versions simultaneously. This helps you:

- Quickly switch between versions for debugging
- Run test suites against both versions
- Gradually deploy changes to production
- Maintain backwards compatibility during upgrades

---

## Setting Up Dual-Boot with next_rails

The fastest way to set up dual-booting is with the [next_rails](https://github.com/fastruby/next_rails) gem.

### Installation

```bash
gem install next_rails
next --init
```

This creates:
- `Gemfile.next` - Symlink to your Gemfile
- `Gemfile.next.lock` - Lock file for the next Rails version

### How It Works

The `next_rails` gem provides a `next?` helper method that you can use in your Gemfile:

```ruby
# Gemfile

def next?
  File.basename(__FILE__) == "Gemfile.next"
end

if next?
  gem 'rails', '~> 7.0.0'
else
  gem 'rails', '~> 6.1.0'
end
```

### Running Commands

```bash
# Run with current Rails version
bundle exec rails server
bundle exec rspec

# Run with next Rails version
BUNDLE_GEMFILE=Gemfile.next bundle exec rails server
BUNDLE_GEMFILE=Gemfile.next bundle exec rspec

# Or use the next command
next bundle exec rails server
next bundle exec rspec
```

---

## Gemfile Configuration Examples

### Basic Rails Version Switching

```ruby
# Gemfile

def next?
  File.basename(__FILE__) == "Gemfile.next"
end

if next?
  gem 'rails', '~> 7.0.0'
else
  gem 'rails', '~> 6.1.0'
end

# Common gems that work with both versions
gem 'devise', '>= 4.8'
gem 'sidekiq', '>= 6.0'
```

### Handling Gem Version Differences

When gems need different versions for different Rails versions:

```ruby
# Gemfile

def next?
  File.basename(__FILE__) == "Gemfile.next"
end

if next?
  gem 'rails', '~> 7.0.0'
  gem 'activeadmin', '~> 3.0'
  gem 'ransack', '~> 4.0'
else
  gem 'rails', '~> 6.1.0'
  gem 'activeadmin', '~> 2.9'
  gem 'ransack', '~> 2.6'
end
```

### Complete Example

```ruby
# Gemfile

source 'https://rubygems.org'

def next?
  File.basename(__FILE__) == "Gemfile.next"
end

# Rails version
if next?
  gem 'rails', '~> 7.0.0'
else
  gem 'rails', '~> 6.1.0'
end

# Database
gem 'pg', '~> 1.4'

# Authentication
if next?
  gem 'devise', '~> 4.9'
else
  gem 'devise', '~> 4.8'
end

# Background jobs
gem 'sidekiq', '~> 7.0'

# Testing (development/test only)
group :development, :test do
  gem 'rspec-rails', next? ? '~> 6.0' : '~> 5.1'
  gem 'factory_bot_rails'
end
```

---

## Dual-Boot in Different Environments

### Development

Quickly switch between versions to debug unexpected behavior:

```bash
# Start server with current version
rails server

# Start server with next version (different port)
BUNDLE_GEMFILE=Gemfile.next rails server -p 3001
```

### Test

Run test suites against both versions:

```bash
# Run tests with current version
bundle exec rspec

# Run tests with next version
BUNDLE_GEMFILE=Gemfile.next bundle exec rspec
```

### Production (Gradual Rollout)

Deploy to a percentage of traffic:

1. Deploy next version to a subset of servers
2. Monitor error rates and performance
3. Gradually increase traffic percentage
4. Roll back if issues arise

---

## CI Configuration

### CircleCI

Add a second job for the next Rails version:

```yaml
# .circleci/config.yml

version: 2.1

jobs:
  build-current:
    docker:
      - image: cimg/ruby:3.1.0
        environment:
          RAILS_ENV: test
          DATABASE_URL: postgres://postgres@localhost/myapp_test
      - image: cimg/postgres:14.0
    steps:
      - checkout
      - run: bundle install
      - run: bundle exec rails db:create db:schema:load
      - run: bundle exec rspec

  build-next:
    docker:
      - image: cimg/ruby:3.1.0
        environment:
          RAILS_ENV: test
          DATABASE_URL: postgres://postgres@localhost/myapp_test
          BUNDLE_GEMFILE: Gemfile.next
      - image: cimg/postgres:14.0
    steps:
      - checkout
      - run: bundle install
      - run: bundle exec rails db:create db:schema:load
      - run: bundle exec rspec

workflows:
  version: 2
  test:
    jobs:
      - build-current
      - build-next
```

### Travis CI

```yaml
# .travis.yml

language: ruby
cache: bundler

rvm:
  - 3.1.0

gemfile:
  - Gemfile
  - Gemfile.next

services:
  - postgresql

before_script:
  - bundle install
  - bundle exec rails db:create db:schema:load

script:
  - bundle exec rspec
```

### GitHub Actions

```yaml
# .github/workflows/ci.yml

name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    strategy:
      matrix:
        gemfile: [Gemfile, Gemfile.next]

    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432

    env:
      BUNDLE_GEMFILE: ${{ matrix.gemfile }}
      DATABASE_URL: postgres://postgres:postgres@localhost/myapp_test
      RAILS_ENV: test

    steps:
      - uses: actions/checkout@v3

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1
          bundler-cache: true

      - name: Setup Database
        run: |
          bundle exec rails db:create
          bundle exec rails db:schema:load

      - name: Run Tests
        run: bundle exec rspec
```

---

## Branch Strategy

### Create the Rails Upgrade Branch

After adjusting dependencies for both Rails versions:

```bash
# Create the upgrade branch
git checkout -b rails-next-version

# Commit dual-boot setup
git add Gemfile Gemfile.next Gemfile.next.lock
git commit -m "Add dual-boot setup for Rails upgrade"

# Push and open PR (targeting main)
git push -u origin rails-next-version
```

### Workflow

1. **Main branch** - Current Rails version, production-ready
2. **rails-next-version branch** - Contains dual-boot code and upgrade fixes
3. **Feature branches** - Target either main (backwards-compatible) or rails-next-version (breaking changes)

### Pull Request Strategy

**For backwards-compatible changes:**
- Target: `main`
- Merge and deploy immediately
- Automatically included in rails-next-version via rebases

**For breaking changes:**
- Target: `rails-next-version`
- Test with both versions
- Will be deployed only after upgrade complete

---

## Caveats

### Test Suite Duration

If your test suite takes 3 hours, dual-booting doubles it to 6 hours. Consider:

- Running both versions only on main branch merges
- Running next version tests nightly instead of on every commit
- Parallelizing test runs

### Memory Usage

Running two versions requires more memory. Monitor your CI resources.

### Gem Conflicts

Some gems may have incompatible dependencies. Use bundler's conflict resolution:

```bash
# See why a gem can't be installed
bundle install
# If conflicts, check the error message

# Force specific versions if needed
bundle update --conservative gem_name
```

---

## When to Use Dual-Boot

**Use dual-boot when:**
- Upgrading a large application
- The team needs time to fix issues incrementally
- You want to deploy changes gradually
- CI/CD pipeline supports multiple configurations

**Skip dual-boot when:**
- Application is small and simple
- Test suite is fast
- Upgrade can be completed in one sprint
- Limited CI resources

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `next --init` | Initialize dual-boot |
| `next bundle install` | Install next version gems |
| `next bundle exec rspec` | Run tests with next version |
| `BUNDLE_GEMFILE=Gemfile.next` | Environment variable for next version |

---

## Resources

- [next_rails gem](https://github.com/fastruby/next_rails)
- [FastRuby.io Blog](https://www.fastruby.io/blog)
- [Dual Boot Rails Article](https://www.fastruby.io/blog/upgrade-rails/dual-boot/dual-boot-with-rails.html)
