# Code Moto

Code Moto is a shared foundation for building and maintaining apps. It brings a Rails API, a React website, native Apple apps, and project tooling into one repository, so new projects can start with the same development, testing, deployment, and release workflow.

Projects built on Code Moto keep their own Git history and configuration, and can merge improvements from this repository as the foundation evolves. Components can be added or removed to suit each project.

## What's included

- **Backend:** Ruby on Rails with PostgreSQL and GoodJob background jobs.
- **Frontend:** React, TypeScript, Vite, and Tailwind CSS, with separate sites for configured subdomains.
- **Apps:** Swift apps targeting iOS, macOS, and tvOS, with simulator and App Store publishing tools.
- **Operations:** Server provisioning and deployment, backups, and shared Ruby gems.

## Local development

Install mise and PostgreSQL, and have PostgreSQL running locally. Apple app development and tests also require macOS with Xcode.

1. Run `mise install` to install the tool versions pinned in `mise.toml`.
2. Create `.env.development` and `.env.production` from `.env.default` and fill in the required values. Projects registered in Mr. Moto with 1Password references can generate them by running Mr. Moto's `mr secrets` in the checkout instead.
3. Run `mise dependencies` to install project dependencies.
4. Run `mise db:migrate` to prepare the development database.
5. Run `mise start` to start the API, background jobs, and frontend sites. It prints the local URLs; the API runs at `http://localhost:3000`.

Non-secret project settings live in `config.json`, including the domain, GitHub repository, database name, subdomains, and app release details. Application credentials live in the gitignored `.env.*` files. Linear, GitHub/Forgejo PR operations, and macOS release uploads use Mr. Moto's central commands; repository-local tokens are not supported.

## Common commands

| Command | Purpose |
| --- | --- |
| `mise test` | Run all test suites, including frontend type checking |
| `mise tsc` | Type-check the frontend |
| `mise console` | Open the Rails development console |
| `mise simulate iphone` | Launch the iPhone app in a simulator |
| `mise xcode` | Open the Apple app project |

Deployment, basis merges, and publishing use the project-specific instructions in [.agents/skills](.agents/skills). Mr. Moto owns card tracking, enqueueing, and the review workflow.

## Starting another project

Run `mise spawn example.com` from this repository to create a sibling checkout with project configuration and generated environment files. Create its GitHub repository and review its configuration and credentials before using it. Repository registration and scheduling are handled separately by [Mr. Moto](https://github.com/grahamotte/MrMoto). Downstream projects use the merge skill to bring in updates from Code Moto without replacing their history.

## Repository guide

| Directory | Contents |
| --- | --- |
| `backend/` | Rails API and background jobs |
| `frontend/` | React sites and shared frontend code |
| `apps/` | Native apps and screenshots |
| `gems/` | Shared Ruby libraries |
| `deploy/` | Infrastructure and deployment tooling |
| `publish/` | App versioning, simulation, and publishing |
| `manager/` | Project creation and Code Moto merges |
| `scripts/` | Scripts behind mise tasks |

See [manager](docs/manager.md) for how Code Moto works with Mr. Moto, [Apple credentials](docs/apple-credentials.md) for publishing setup, and [AGENTS.md](AGENTS.md) for contribution rules.
