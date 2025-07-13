# Mastodon on Oracle Cloud's always free tier with Terraform and Ansible

This sets up a single node instance, which should be large enough for most users. Elasticsearch is included, so you can search your toots, favourites, bookmarks, and (since 4.2) any public posts from users who opted in.

Based loosely on https://github.com/xmflsct/oracle-arm-mastodon and https://github.com/mastodon/mastodon/blob/main/docker-compose.yml .

This is how I set up my [personal account](https://social.glyphy.com/@dv).

[Here's an alternate Ansible playbook](https://github.com/l3ib/mastodon-ansible) that doesn't use Docker.

## Step 1: Prerequisites

1. Create an [Oracle Cloud](https://www.oracle.com/cloud/) account. You just need the free tier.
2. Create a tenancy and a compartment. Your home region should be geographically close to you for speeeeeed.
3. [Generate an API key](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#apisigningkey_topic_How_to_Generate_an_API_Signing_Key_Console) . You should now have `~/.oci/config`.
4. [Install Terraform](https://developer.hashicorp.com/terraform/downloads). I used [homebrew](https://brew.sh/).
5. [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html). I used [homebrew](https://brew.sh/).
6. If, like me, you use [Cloudflare](https://www.cloudflare.com/) for their free DNS service, [create an API key](https://github.com/caddy-dns/cloudflare#authenticating), so Caddy can configure a TLS cert without having to listen on port 80.
    * If you don't use Cloudflare, you'll need to make two changes. Remove all references to "cloudflare" from `roles/mastodon/templates/Caddyfile` and uncomment the port 80 ingress rules in `terraform/main.tf`.
7. You'll need a way to send email via SMTP for Mastodon account setup and management. I use [Sendgrid](https://sendgrid.com/)'s free tier for this, which doesn't allow for a lot of email to be sent out per day. This works for me because I disable email notifications in my Mastodon account anyway. If this is a problem for you, I hear Mailgun may be more permissive.

### [Optional] Step 1.1: Pushover and Healthchecks.io for cron failures

Cron runs a Mastodon backup (optional) as well as a Docker cleanup task to control disk space usage.

[Healtchecks.io](https://healthchecks.io/) is great for tracking when these jobs aren't completing due to errors. It has a generous free tier, which is more than enough for our purposes. Create an account, a project, and a check, then record the URL. It should look like `https://hc-ping.com/<some id>`. For now HC.io is only used for the backup job (see below). If you have your own backup strategy, you can skip this.

With a [Pushover.net](https://pushover.net/) account you can get a push message on your phone if a cron run fails. It's a one-time payment for their mobile app.

### [Optional] Step 1.2: Backups with [Kopia.io](https://kopia.io/)

Kopia can back up to many destinations. [Its setup](https://kopia.io/docs/getting-started/) is outside the scope of this doc. You can skip this to get Mastodon running and set it up later. It won't impact how Mastodon runs.

1. After setting up the repo and connecting to it, copy the generated `repository.config` into `roles/mastodon/templates/kopia-repository.config`.
2. If you're using rclone, also copy the `rclone.conf` file to the same directory.
3. I would recommend running `kopia repository connect` from your own machine (install it there if needed), enabling compression to save space, and disabling a bunch of not-very-compressible extensions (case-sensitive, unfortunately):
    ```bash
   # If, like me, you used rclone, replace <rclone-repo-name> with the name from rclone.conf
   # Adjust the rclone-args path as needed, or remove if you didn't need rclone
   kopia repository connect rclone --remote-path=<rclone-repo-name>:/kopia --rclone-args="--config=roles/mastodon/templates/rclone.conf"

   # Enable compression
   kopia policy set global --compression pgzip

   # Disable compression for common media files
   kopia policy set --global --add-never-compress=.jpg --add-never-compress=.jpeg --add-never-compress=.JPG --add-never-compress=.JPEG
   --add-never-compress=.png --add-never-compress=.PNG --add-never-compress=.mov --add-never-compress=.MOV --add-never-compress=.mp4
   --add-never-compress=.MP4 --add-never-compress=.avi --add-never-compress=.AVI --add-never-compress=.JPEG --add-never-compress=.png
   --add-never-compress=.PNG --add-never-compress=.mov --add-never-compress=.MOV --add-never-compress=.mp4 --add-never-compress=.MP4
   --add-never-compress=.avi --add-never-compress=.AVI --add-never-compress=.JPEG --add-never-compress=.png --add-never-compress=.PNG
   --add-never-compress=.mov --add-never-compress=.MOV --add-never-compress=.mp4 --add-never-compress=.MP4 --add-never-compress=.avi
   --add-never-compress=.AVI --add-never-compress=.JPEG --add-never-compress=.png --add-never-compress=.PNG --add-never-compress=.mov
   --add-never-compress=.MOV --add-never-compress=.mp4 --add-never-compress=.MP4 --add-never-compress=.avi --add-never-compress=.AVI
   ```

### [Optional] Step 1.3: Observability with [Newrelic](https://newrelic.com/)

A free account with Newrelic will allow you to set up their agent on the instance, which will send metrics that you can see on https://one.newrelic.com/ . Then you can set up alerts there to be notified if you're running out of disk space and such.

1. [Install the Ansible Galaxy collection](https://galaxy.ansible.com/newrelic/newrelic-infra)
2. Get a license key from their Web UI

## Step 2: Provision infra with Terraform

1. In `terraform/` create a file called `terraform.tfvars`. The format is:
   ```terraform
   tenancy_ocid        = "ocid1..."
   compartment_ocid    = "ocid1..."
   instance_image_ocid = "ocid1..."
   ssh_public_key      = "ssh-ed25519 ..."
   ```
   Fill these out with info from the previous step. See comments in `main.tf` for more instructions.
2. From the `terraform` directory run `terraform init`.
3. Then run `terraform apply`. Fix any errors, then review the plan and enter "yes" to provision the infra.
4. Note the IP address at the end of the process. You should be able to `ssh ubuntu@<ip>` to log into your compute instance.
5. Add an "A" record in your DNS provider to point at this IP for your Mastodon (sub)domain. This is the `web_domain` in Ansible vars below. If you're using Cloudflare you can enable its proxying capability. It doesn't seem to interfere with ActivityPub traffic.

## Step 3: Set up Mastodon

1. Update `inventory.ini` and set the IP for the "oci" host to the one from the previous step.
2. Configure Ansible variables in `group_vars/mastodon/vars.yaml`.
3. If your `web_domain` is not the same as `local_domain`, you'll need to [set up a webfinger forward](https://docs.joinmastodon.org/admin/config/#web_domain) on the latter to point to the former.
    * I use an Apache-compatible web server on glyphy.com, so I added the following to my .htaccess:
        ```
        # Mastodon
        RewriteRule ^.well-known/host-meta(.*)$ https://social.glyphy.com/.well-known/host-meta$1 [L,R=301]
        RewriteRule ^.well-known/webfinger(.*)$ https://social.glyphy.com/.well-known/webfinger$1 [L,R=301]
        ```
4. If you don't want to leave secrets in plain-text, configure them in `group_vars/mastodon/vault.yaml`. Otherwise, just update the `vault_` references in `vars.yaml`.
    * You'll need to set up [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) for this.
    * Note that Mastodon-specific vars like `otp_secret` are not known until later, so leave those empty for now.
5. Create a filesystem for the attached block volume by running `ansible-playbook mastodon.yaml --tags bootstrap`. This will wipe everything on it. If you're attaching a formatted disk, don't run this. Instead, just create an empty file called `.ansible-check` in the `root` variable location from `vars.yaml` above. This bootstrap process only needs to be done once.
6. (Optional) Apply any upstream patches to modify Mastodon itself
   1. Clone [the mastodon repo](https://github.com/mastodon/mastodon)
   2. Make changes to the source code as needed. For example,
      [extend the default timeline length](https://github.com/mastodon/mastodon/issues/2301) or
      [increase the post size](https://write.as/sweetmeat/customize-mastodon-to-change-your-post-character-limit).
   3. Run `git diff` and save the output to `roles/mastodon/files/mastodon.patch`. This will get applied in the next step. Example patch:
      ```
      diff --git a/app/lib/feed_manager.rb b/app/lib/feed_manager.rb
      index 510667558..96b05edf8 100644
      --- a/app/lib/feed_manager.rb
      +++ b/app/lib/feed_manager.rb
      @@ -7,12 +7,12 @@ class FeedManager
         include Redisable

         # Maximum number of items stored in a single feed
      -  MAX_ITEMS = 400
      +  MAX_ITEMS = 4000

         # Number of items in the feed since last reblog of status
         # before the new reblog will be inserted. Must be <= MAX_ITEMS
         # or the tracking sets will grow forever
      -  REBLOG_FALLOFF = 40
      +  REBLOG_FALLOFF = 400

         # Execute block for every active account
         # @yield [Account]
      ```
7. Run the full playbook to set up the rest of the stack: `ansible-playbook mastodon.yaml`
    * You can add `-C` for a dry run to see what would happen without actually making any changes.
    * You can rerun this later if you make any config changes.
    * If you don't want to use the Kopia backups or want to set them up later, add `--skip-tags backup`
    * If you don't want to install the Newrelic agent, add `--skip-tags newrelic`
8. Run the [one-time Mastodon bootstrapping setup](https://docs.joinmastodon.org/admin/setup/)
    * From the root directory (/mnt/mastodon by default): `docker-compose run -e RAILS_ENV=production -- web setup bundle exec rake mastodon:setup`. This should output some environment variables. You'll find the missing secrets here. Copy their values into `group_vars/mastodon/vault.yaml` (use `ansible-vault edit vault.yaml` to edit and re-encrypt).
    * You should be able to also set up the admin user via this step. I got a cryptic error when I did this, but I was able to use the reset password function later to recover the password.
    * Re-run the playbook from the previous step (with any `--skip-tags` you need) to reconfigure and restart Mastodon.
    * You should now be able to log in and start using Mastodon!
9. (Optional) To connect your new instance to the wider Fediverse and make discovery easier, you may want to add one of the relays from [this list](https://joinfediverse.wiki/index.php?title=Fediverse_relays). Go to Settings > Administration > Relays.
    * Note that some relays require your server to be up for a couple of weeks before they approve your join request.
    * Also make sure to do some research on the relay owners (by checking relay members and its top-level domain), as some may be run by communities/organizations you may find objectionable.

## Next Steps: Discovery

Being on a solo instance can be quite lonely. Mastodon's design [makes it hard for single-user instances to discover what's going on in the Fediverse] (https://jvns.ca/blog/2023/08/11/some-notes-on-mastodon/#downsides-to-being-on-a-single-person-server). Additionally, unless you're following some very active accounts, your instance's CPU usage may be so low that Oracle may deem it unused and try to delete it. They'll email you to give you a heads-up, but (fortunately?) improving discovery also adds CPU load.

**Warning: adding relays will likely greatly increase the amount of storage your instance requires. See the Tuning section below.**

### FediBuzz relay

You can subscribe to hashtags using [the excellent FediBuzz relay](https://relay.fedi.buzz/). This is different from just following a hashtag via Mastodon UI. The latter just filters the posts your server already knows about, while the former tells your server about posts it may have never seen.

This relay relies on being able to consume an instance's public posts anonymously, which is prone to abuse, so starting with Mastodon 4.2 this functionality requires an API token. If you like this tool and want to support its effectiveness, you can [donate an API token](https://fedi.buzz/token/donate). This essentially lets FediBuzz see the posts your server sees and then broadcast them out to other servers that subscribe to the relay. Because this also allows FediBuzz to see your DMs, you can create a separate user on your instance. The following creates a "fedibuzz" user on your instance:

1. From `/mnt/mastodon`, `docker-compose exec web bash`
2. `tootctl accounts create fedibuzz --email another_email@example.com` (password will be auto-generated)
3. Either log out or open the confirmation link in the email in a private browser window, update password and set up 2FA (optional)
4. I didn't get an approval email, so I ran `tootctl accounts modify fedibuzz --approve` to approve the account.
5. Then just paste your instance domain on https://fedi.buzz/token/donate

### Open relays

If you just want an unfiltered firehose of posts from other instances, there are some public relays out there:

1. https://relaylist.com/
2. https://joinfediverse.wiki/index.php?title=Fediverse_relays

## Next Steps: Tuning

If you added some relays (see previous section) your instance will start having to store a lot more posts, including the images included within them. This can quickly burn through the free tier storage. I recommend going to `Settings > Administration > Server Settings > Content retention` and setting "Media cache retention period" to something short like 3 days. If you view a post with some media on day 4 your Mastodon client will just fetch the missing media from the origin server on the fly.

## Upgrading

Generally, the upgrade process is:

1. On the remote host, run a backup if you have configured them: `/mnt/mastodon/backup.sh`
2. Back on your local machine, set `mastodon_version` in `group_vars/mastodon/vars.yaml`
3. Run `ansible-playbook mastodon.yaml`

The playbook will build the new image, run the migration scripts, rebuild the search index, and restart Mastodon services.

If you want to speed up the process, and you're sure all the versions between your current and the one you're upgrading to don't require migrations you can skip them with `ansible-playbook mastodon.yaml --skip-tags=migrations` .

## Troubleshooting

### Can't access web domain

* Check that you can resolve the domain to the IP address of your compute instance.
* Run `docker-compose logs caddy` and confirm that it was able to successfully provision a certificate. If you're not using Cloudflare and it's timing out, remember to open port 80 in Terraform's main.tf and rerun `terraform apply`.

### Something else

First of all, check the official docs: https://docs.joinmastodon.org/admin/troubleshooting/

No promises, but feel free to open an issue in this repo, and I'll try to help.
