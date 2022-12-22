# Mastodon on Oracle Cloud's always free tier with Terraform and Ansible

Based loosely on https://github.com/xmflsct/oracle-arm-mastodon and https://github.com/mastodon/mastodon/blob/main/docker-compose.yml .

This is how I set up my [@dv@glyphy.com account](https://social.glyphy.com/@dv).

[Here's an alternate Ansible playbook](https://github.com/l3ib/mastodon-ansible) that doesn't use Docker.

## Step 1: Prerequisites

1. Create an [Oracle Cloud](https://www.oracle.com/cloud/) account. You just need the free tier.
2. Create a tenancy and a compartment. Your home region should be geographically close to you for speeeeeed.
3. [Generate an API key](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#apisigningkey_topic_How_to_Generate_an_API_Signing_Key_Console)
   . You should now have `~/.oci/config`.
4. [Install Terraform](https://developer.hashicorp.com/terraform/downloads). I used [homebrew](https://brew.sh/).
5. [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html). I
   used [homebrew](https://brew.sh/).
6. If, like me, you use [Cloudflare](https://www.cloudflare.com/) for their free DNS
   service, [create an API key](https://github.com/caddy-dns/cloudflare#authenticating), so Caddy can configure a TLS cert without having to
   listen on port 80.
    * If you don't use Cloudflare, you'll need to make two changes. Remove all references to "cloudflare" from
      `roles/mastodon/templates/Caddyfile` and uncomment the port 80 ingress rules in `terraform/main.tf`.
7. You'll need a way to send email via SMTP for Mastodon account setup and management. I use [Sendgrid](https://sendgrid.com/)'s free
   tier for this, which doesn't allow for a lot of email to be sent out per day. This works for me because I disable email notifications
   in my Mastodon account anyway. If this is a problem for you, I hear Mailgun may be more permissive.

### [Optional] Step 1.1: Pushover and Healthchecks.io for cron failures

Cron runs a Mastodon backup (optional) as well as a Docker cleanup task to control disk space usage.

[Healtchecks.io](https://healthchecks.io/) is great for tracking when these jobs aren't completing due to errors. It has a generous free
tier, which is more than enough for our purposes. Create an account, a project, and a check, then record the URL. It should look like
`https://hc-ping.com/<some id>`. For now HC.io is only used for the backup job (see below). If you have your own backup strategy, you
can skip this.

With a [Pushover.net](https://pushover.net/) account you can get a push message on your phone if a cron run fails. It's a $5 USD
one-time payment for their mobile app.

### [Optional] Step 1.2: Backups with [Kopia.io](https://kopia.io/)

Kopia can back up to many destinations. [Its setup](https://kopia.io/docs/getting-started/) is outside the scope of this doc.
You can skip this to get Mastodon running and set it up later. It won't impact how Mastodon runs.

1. After setting up the repo and connecting to it, copy the generated `repository.config`
   into `roles/mastodon/templates/kopia-repository.config`.
2. If you're using rclone, also copy the `rclone.conf` file to the same directory.
3. I would recommend running `kopia repository connect` from your own machine (install it there if needed), enabling compression to save
   space, and disabling a bunch of not-very-compressible extensions (case-sensitive, unfortunately):
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

A free account with Newrelic will allow you to set up their agent on the instance, which will send metrics that you can see on
https://one.newrelic.com/ . Then you can set up alerts there to be notified if you're running out of disk space and such.

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
5. Add an "A" record in your DNS provider to point at this IP for your Mastodon (sub)domain. This is the `web_domain` in Ansible vars
   below. If you're using Cloudflare you can enable its proxying capability. It doesn't seem to interfere with ActivityPub traffic.

## Step 3: Set up Mastodon

1. Update `inventory.ini` and set the IP for the "oci" host to the one from the previous step.
2. Configure Ansible variables in `group_vars/mastodon/vars.yaml`.
3. If your `web_domain` is not the same as `local_domain`, you'll need
   to [set up a webfinger forward](https://docs.joinmastodon.org/admin/config/#web_domain) on the latter to point to the former.
    * I use an Apache-compatible web server on glyphy.com, so I added the following to my .htaccess:
        ```
        # Mastodon
        RewriteRule ^.well-known/host-meta(.*)$ https://social.glyphy.com/.well-known/host-meta$1 [L,R=301]
        RewriteRule ^.well-known/webfinger(.*)$ https://social.glyphy.com/.well-known/webfinger$1 [L,R=301]
        ```
4. If you don't want to leave secrets in plain-text, configure them in `group_vars/mastodon/vault.yaml`. Otherwise, just update the
   `vault_` references in `vars.yaml`.
    * You'll need to set up [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) for this.
    * Note that Mastodon-specific vars like `otp_secret` are not known until later, so leave those empty for now.
5. Create a filesystem for the attached block volume by running `ansible-playbook mastodon.yaml --tags bootstrap`. This will wipe
   everything on it. If you're attaching a formatted disk, don't run this. Instead, just create an empty file called `.ansible-check` in
   the `root` variable location from `vars.yaml` above. This bootstrap process only needs to be done once.
6. Run the full playbook to set up the rest of the stack: `ansible-playbook mastodon.yaml`
    * You can add `-C` for a dry run to see what would happen without actually making any changes.
    * You can rerun this later if you make any config changes.
    * If you don't want to use the Kopia backups or want to set them up later, add `--skip-tags backup`
    * If you don't want to install the Newrelic agent, add `--skip-tags newrelic`
7. Run the [one-time Mastodon bootstrapping setup](https://docs.joinmastodon.org/admin/setup/)
    * From the root directory (/mnt/mastodon by default): `docker-compose run -e RAILS_ENV=production setup bundle exec rake
      mastodon:setup`. This should output some environment variables. You'll find the missing secrets here. Copy their values into
      `group_vars/mastodon/vault.yaml` (use `ansible-vault edit vault.yaml` to edit and re-encrypt).
    * You should be able to also set up the admin user via this step. I got a cryptic error when I did this, but I was able to use the
      reset password function later to recover the password.
    * Re-run the playbook from the previous step (with any `--skip-tags` you need) to reconfigure and restart Mastodon.
    * You should now be able to log in and start using Mastodon!

## Troubleshooting

### Can't access web domain

* Check that you can resolve the domain to the IP address of your compute instance.
* Run `docker-compose logs caddy` and confirm that it was able to successfully provision a certificate. If you're not using Cloudflare
  and it's timing out, remember to open port 80 in Terraform's main.tf and rerun `terraform apply`.

### Something else

First of all, check the official docs: https://docs.joinmastodon.org/admin/troubleshooting/

No promises, but feel free to open an issue in this repo, and I'll try to help.
