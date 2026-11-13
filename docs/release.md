# Releases and deploys

How code reaches DEV and PROD on every Drupal site we build. Deploys run in GitHub
Actions only, never from a developer's machine.

| Environment | Deployed | By |
|---|---|---|
| DEV | `dev`, on every push to it and after each release's reset of `dev` | `.github/workflows/deploy-dev.yml` |
| PROD | a release tag `YYYY-MM-DD-N` (e.g. `2026-11-13-1`), when it is created | `.github/workflows/deploy-prod.yml` |

Both call the reusable workflow `.github/workflows/deploy.yml` in this repository,
which runs [Deployer](https://deployer.org) with the recipe `deployer/drupal.php`. The
site's `deploy.php` only lists its hosts.

## What a deploy does

1. **Builds in Actions**: checks out the branch or tag and runs
   `composer install --no-dev` with the PHP version in `.ddev/config.yaml`. The
   servers need neither access to GitHub nor Composer.
2. **Uploads** the build with rsync to a new release, `{{deploy_path}}/releases/<n>`.
3. **Links** what is kept between releases, from `{{deploy_path}}/shared`: `.env.local`
   (see [settings.php and secrets](settings.md)), `web/sites/default/files` and
   `private`.
4. **Runs `drush deploy`** in the new release: database updates, config import, cache
   rebuild and deploy hooks. If it fails, the deploy stops and the site keeps running
   the previous release.
5. **Writes the commit** to `web/ref.txt` (and `REVISION`), so anyone can see what a
   server runs: `curl -s https://<site>/ref.txt`.
6. **Switches** `{{deploy_path}}/current` to the new release and reloads PHP-FPM,
   which also clears the opcode cache.
7. **Keeps five releases**.

## Releasing

A maintainer of the site (see [the maintainers team](workflow.md#the-maintainers-team)):

```sh
just release
```

It tags the default branch on GitHub with today's date, `YYYY-MM-DD-N`, and creates
a GitHub release whose notes list the merged pull requests. The tag then deploys to
PROD, and resets `dev` (see [dev](workflow.md#dev)). Follow it with `gh run watch`.

**Redeploy or roll back:** in the site's repository on GitHub, Actions, deploy-prod,
Run workflow, and choose the tag under "Use workflow from". Rolling back this way
imports the older release's config, but database updates that already ran are not
undone: a release with update hooks may need a fix in a new release instead.

**Hotfix while the default branch holds work that isn't ready:** branch from the
release on PROD, fix it in a pull request to the default branch, and release the
branch itself before it is merged:

```sh
git switch -c 123-hotfix-description 2026-11-13-1
# commit the fix, push and open the pull request
gh release create 2026-11-14-1 --target 123-hotfix-description --title 2026-11-14-1 --generate-notes
```

## Setting up a server

The server runs the site as the user `deploy`, which owns `{{deploy_path}}` and runs
PHP-FPM's pool. It needs PHP CLI of the same version as `.ddev/config.yaml`, rsync,
and the site's database, with the site in it, before the first deploy: that deploy
already runs `drush deploy`, which also refuses an empty `config/sync`, so the site's
config must be exported and committed. The web server's document root is
`{{deploy_path}}/current/web`.

Replace `<site>`, `<env>` (`dev` or `prod`), `<ip>`, `<deploy_path>` and the PHP
version below.

1. **A key pair for GitHub Actions**, on your machine:

   ```sh
   ssh-keygen -t ed25519 -N '' -C "github-actions <site> <env>" -f ./deploy-<site>-<env>
   ```

2. **The public key on the server**, as the admin user (`ubuntu`):

   ```sh
   sudo -u deploy mkdir -p -m 700 /home/deploy/.ssh
   echo '<content of deploy-<site>-<env>.pub>' | sudo -u deploy tee -a /home/deploy/.ssh/authorized_keys > /dev/null
   ```

3. **Let deploy reload PHP-FPM, and nothing else**, as `ubuntu`:

   ```sh
   echo 'deploy ALL=(root) NOPASSWD: /usr/bin/systemctl reload php8.4-fpm' | sudo tee /etc/sudoers.d/deploy-php-fpm > /dev/null
   sudo chmod 440 /etc/sudoers.d/deploy-php-fpm
   sudo visudo -c
   ```

4. **The shared directories and `.env.local`**, as `ubuntu`, then write `.env.local`
   as [settings.php and secrets](settings.md#creating-envlocal) says, at
   `<deploy_path>/shared/.env.local`:

   ```sh
   sudo -u deploy mkdir -p <deploy_path>/shared/web/sites/default/files <deploy_path>/shared/private
   ```

5. **The GitHub environment**, from the site's checkout. It holds the private key and
   the server's host keys. Then delete the key files:

   ```sh
   gh api -X PUT "repos/{owner}/{repo}/environments/<env>" --silent
   gh secret set DEPLOY_SSH_KEY --env <env> < ./deploy-<site>-<env>
   gh variable set DEPLOY_KNOWN_HOSTS --env <env> --body "$(ssh-keyscan -t ed25519 <ip> 2>/dev/null)"
   rm ./deploy-<site>-<env> ./deploy-<site>-<env>.pub
   ```

6. **The host in `deploy.php`**: the IP address (a domain behind the Cloudflare proxy
   doesn't reach SSH), `deploy`, the deploy path and the PHP-FPM service. Commit it
   in a pull request.

7. **The first deploy:** for DEV, run deploy-dev from the Actions tab; for PROD,
   `just release`. Check `curl -s https://<site>/ref.txt`.
