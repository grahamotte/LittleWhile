# Code Moto

Code Moto is a shared foundation for building and maintaining apps. It brings a Rails API, a React website, native Apple apps, and project tooling into one repository, so new projects can start with the same development, testing, deployment, and release workflow.

Projects built on Code Moto keep their own Git history and configuration, and can merge improvements from this repository as the foundation evolves. Components can be added or removed to suit each project.

## What's included

- **Backend:** Ruby on Rails with PostgreSQL and GoodJob background jobs.
- **Frontend:** React, TypeScript, Vite, and Tailwind CSS, with separate sites for configured subdomains.
- **Apps:** Swift apps targeting iOS, macOS, and tvOS, with simulator and App Store publishing tools.
- **Operations:** Server provisioning and deployment, backups, and shared Ruby gems.
- **Agent workflow:** A manager that picks up Linear cards, launches coding agents in Git worktrees, and merges approved pull requests.

## Local development

Install mise and PostgreSQL, and have PostgreSQL running locally. Apple app development and tests also require macOS with Xcode.

1. Run `mise install` to install the tool versions pinned in `mise.toml`.
2. Create `.env.development` and `.env.production` from `.env.default` and fill in the required values. Existing projects with configured 1Password references can use `mise manager:secrets` with a service account instead.
3. Run `mise dependencies` to install project dependencies.
4. Run `mise db:migrate` to prepare the development database.
5. Run `mise start` to start the API, background jobs, and frontend sites. It prints the local URLs; the API runs at `http://localhost:3000`.

Non-secret project settings live in `config.json`, including the domain, GitHub repository, database name, subdomains, agent defaults, and app release details. Credentials live in the gitignored `.env.*` files.

## Common commands

| Command | Purpose |
| --- | --- |
| `mise test` | Run all test suites, including frontend type checking |
| `mise tsc` | Type-check the frontend |
| `mise console` | Open the Rails development console |
| `mise simulate iphone` | Launch the iPhone app in a simulator |
| `mise xcode` | Open the Apple app project |
| `mise manager:trigger` | Process eligible cards for the configured Linear team |

Deployment, upstream merges, and publishing follow the card and pull request workflow described in [AGENTS.md](AGENTS.md), using the corresponding skills in [.agents/skills](.agents/skills).

## Starting another project

Run `mise spawn example.com` from this repository to create a sibling checkout with project configuration and generated environment files. Create its GitHub repository and review its configuration and credentials before using it. Downstream projects use the merge skill to bring in updates from Code Moto without replacing their history.

## Repository guide

| Directory | Contents |
| --- | --- |
| `backend/` | Rails API and background jobs |
| `frontend/` | React sites and shared frontend code |
| `apps/` | Native apps and screenshots |
| `gems/` | Shared Ruby libraries |
| `deploy/` | Infrastructure and deployment tooling |
| `publish/` | App versioning, simulation, and publishing |
| `manager/` | Linear workflow, agent runners, and project creation |
| `scripts/` | Scripts behind mise tasks |

See [manager runners and labels](docs/manager.md) for agent configuration, [Apple credentials](docs/apple-credentials.md) for publishing setup, and [AGENTS.md](AGENTS.md) for contribution rules.
