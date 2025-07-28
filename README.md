# notebook2app

## Table of Contents

- [Motivation](#motivation)
- [Access](#access)
- [Approach](#approach)
- [Security Concerns](#security-concerns)
- [Limitations](#limitations)
- [Infrastructure](#infrastructure)
    - [Hosting](#hosting)
    - [Deployments](#deployments)
    - [Secret Management](#secret-management)
    - [Ingress, SSL, and DNS](#ingress-ssl-and-dns)

## Motivation

Where I work if you want to deploy a new application, the process is red tap galore. You need a charge code, product line architect approval, and have to submit at least 3 or 4 service now forms to get repos/azure resource groups. Then you've gotta navigate through the internal yaml frameworks to deploy to a dev/test environment and then do risk assessments before prod.

While these processes may work for groups inside a centralized IT organization, *what about everyone else?* If your company isn't primarily a software shop like mine is, you will likely have a ton of domain experts. Inevitably at a big enough company, some of those domain experts learn how to program in their free time. And from what I've observed, their language of choice is almost always Python. They're not always the best with Python. Many struggle with setting up Python and environments locally. However, they're very capable of cobbling together some code and making an app using one of Python's many frontend/backend mashup frameworks like Dash, Gradio, or Streamlit. They also don't typically make anything too complicated. The apps usually just take some inputs, run an algorithm, and spit out some result. 

To me, this category of *domain expert apps* is both under-served and a significant value capture opportunity. I've been maintaining a JupyterHub service in AKS for the past couple years. I've used it primarily to support groups/individuals looking to teach internal Python classes, and I was asked recently if the following was possible to deploy apps from a notebook session. Consequently, I hacked together a quick proof of concept to deploy basic python apps to kubernetes from a notebook session on JupyterHub.

## Access

The JupyterHub service is accessible at https://notebook2app.zachary.day. If you would like to request access, feel free to leave a Github Issue.

## Approach

I took a basically python script that I had made in my downtime at work and made a basic package out of it ([notebook2app package](pkg/src/notebook2app/)). It uses Jinja to format kubernetes resources and the Python kubernetes client to deploy those resources. I included this package inside a singleuser jupyterhub image ([Dockerfile](/Dockerfile)), and assigned the singleuser pod a service account with permissions for deployments/services/ingresses/pods/configmaps. This way a user can write an app (e.g. gradio/dash/etc.) in a notebook and use the notebook2app package to deploy it. This looks like the following:

```python
import notebook2app

notebook2app.deploy(
    name              = "gradio",
    notebook_file     = "app.ipynb",
    requirements_file = "requirements.txt",
    command           = "gradio",
)
```

You can [view the example notebooks here](/notebooks/).

## Security Concerns

**DISCLAIMER: I wouldn't ever recommend doing this in production for a number of reasons:**

1. **Generally speaking, it's not a great idea giving people the ability to interact with the kube-apiserver and create/delete/update resources in the jupyterhub namespace from a notebook.** JupyterHub's documentation discourages [assigning service account to user pods](https://z2jh.jupyter.org/en/latest/administrator/security.html#kubernetes-api-access).

2. Package management is definitely a concern. Allowing people to define any requirement is definitely risky (although standalone JupyterHub is already prone to this risk as is unless you have a private package repo or provide curated environments).

This is just a PoC so I've just mitigated risks by enabling Github Oauth with a user whitelist.
If you're at all curious what a more robust approach would look like, there's two methods off the top of my head:

1. Jupyterhub actually supports [baking in custom services with the hub image](https://z2jh.jupyter.org/en/latest/administrator/services.html#services). Their example shows adding a fastapi service that runs alongside the hub. Just doing this would mitigate the kube-apiserver access risks. With this setup, you could just have the user pods make an api call to the hub service which can perform the deployment.

2. Would be interesting to take advantage of git integration that Jupyterhub has. Since I'm already formatting kubernetes resources, if those land in a git repo, ArgoCD can manage the deployments.

## Limitations

As for limitations, there are many. Here's just a few that come to mind:

1. I'm just converting the notebook files to python files with nbconvert and mounting them from a configmap to the deployed pods. Since ConfigMaps have a maximum size of something like ~1mb, it can't be a massive file. Although the scope of this project isn't intended for large apps so it's not a huge concern.

2. Can only deploy apps confined to a single notebook and also no Conda support. 

3. User access to pod logs is absent. The ideal way to do this would be to use something like loki/promtail for collecting logs and exposing a data source for grafana.

## Infrastructure

### Hosting

I was curious to test out EKS. I pay for a KodeKloud Pro subscription which gives me access to time limited sandboxes for AWS/Azure/GCP. So I tried that out, and turns out they're pretty locked down. Ran into several permissions issues deploying EKS via terraform, but fortunately KodeKloud provides resources for [deploying EKS in their AWS sandbox with Terraform](https://github.com/kodekloudhub/amazon-elastic-kubernetes-service-course). This wasn't the end of the permissions issues though. Typically in cloud environments like Azure, when you create a `LoadBalancer` service, the cloud provider will provision their flavor of Load Balancer service in the background. However, you can't have externally facing load balancers in KodeKloud's AWS playground.

Not wanting to spend a bunch of time fiddling with KodeKloud's cloud playground, I just transitioned to [Rackspace Spot](https://spot.rackspace.com/). Have used it previously and only took be an hour to get stuff up and running. It's been my go-to managed Kubernetes provider for personal projects since it released a bit over a year ago. They provide a non-HA managed control plane for free, the nodes are dirt cheap, load balancers are flat rate $10/mo, and ssd storage is only $0.06 for a GB per month. It's perfect for side projects. And from past experience, I hardly ever have nodes pre-empted since I place bids 5-10x higher than current market price. While the market price may spike on occasion, it's only for a very short period of time. For a few nodes each with 8vCPU/30gb mem, I've never paid more than $8/mo. As for comparing it to other cloud providers, it's about as vanilla as you can get for a managed kubernetes offering. 

### Deployments

I'm using ArgoCD with an app of apps pattern. In the `apps/eks` and `apps/rackspace-spot` folders, I've have the ArgoCD Applications for each workload along with a `bootstrap` Application that simply points to its repo path. This way, if I add other Applications to that folder, ArgoCD will automatically detect and deploy new workloads. And for configuraing individual workloads, I use a mix of kustomizations with some helm charts where sensible.

I have a [bootstrap shell script](scripts/bootstrap.sh) that as the name implies, bootstraps ArgoCD. More specifically, it'll install the base kustomizations for ESO (helps to have those CRDs and controller running ahead of time) and ArgoCD. Then installs the bootstrap Application. From there, it's smooth sailing.

### Secret Management

For the past ~3-4 years, I've primarily been using sealed-secrets with a sprinkle of the Azure Keyvault CSI Secret Provider if I'm using AKS (usually to inject a certificate/private key for sealed secrets from azure keyvault). 

However, about a month ago, I started a complete rebuild of my homelab and had been wanting to use the External Secrets Operator for a couple reasons:

1. While I love sealed-secrets because it helps keep my config declaritive, it's a real grind keeping tracking of all the various sealed secrets I have across my clusters.

2. I really wanted to use ESO's secrete templating feature to accomodate workloads that expect secrets with things like special labels/types/annotations or data containing yaml/json content.

Initially when I started my homelab rebuild, I was using the Bitwarden provider which I didn't care too much for. TLDR if you use cert-manager and Issuers with dns01 challenges that require some api token secret, there's a circular dependency between the bitwarden-sdk-server and cert-manager that just isn't super elegant. So I switched to using Hashicorp Vault which I've deployed in an LXC container on Proxmox. Still learning the ins-and-outs, but I have been enjoying it these past few weeks.

I wanted to hack out this PoC project quick, so I just exposed my vault via a Cloudflared tunnel. I then use the `jwt` auth method. You can checkout the `scripts/` folder for more details, but I just acquire the PEM encoded public key used to sign service account tokens. Pretty sure for EKS and AKS, those rotate on a fairly regular basis, but will have to wait and see what happens with Rackspace Spot. 

### Ingress, SSL, and DNS

I took a pretty standard approach here. For acquiring SSL certs, I use cert-manager with a ClusterIssuer performing dns01 challenges via Cloudflare. For DNS records, I use external-dns - again using Cloudflare.

For Ingress, I have been migrating to using Istio in ambient mode with the Gateway API on my homelab out of curiousity. While doing that, I noticed it'd create a LoadBalancer per Gateway resource. That's fine in my homelab because I've got virtually limitless private IPs, but in Rackspace Spot, that'll cost me $10/mo per LoadBalancer. So for this, I ran with ingress-nginx - particularly the one in the kubernetes-sigs Github org and not nginx-ingress from Nginx Inc. 

