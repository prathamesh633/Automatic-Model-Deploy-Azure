# Azure OpenAI Model Deployment Pipeline

This repository contains an automated GitHub Actions pipeline to manage Azure OpenAI Service model deployments (creation and deletion) across multiple environments (`dev`, `uat`, `prod`).

The pipeline uses **OpenID Connect (OIDC)** to securely authenticate with Azure without storing long-lived credentials (such as client secrets) in GitHub.

---

## Directory Structure

```text
├── .github/
│   └── workflows/
│       ├── deploy-aisearch.yml    # Azure AI Search pipeline definition
│       └── deploy-aoai-model.yml  # Azure OpenAI model pipeline definition
├── env/
│   ├── dev/
│   │   └── config.yml             # Dev environment config (OpenAI)
│   ├── uat/
│   │   └── config.yml             # UAT environment config (OpenAI)
│   └── prod/
│       └── config.yml             # Prod environment config (OpenAI)
├── env-2/
│   ├── dev/
│   │   └── config.yml             # Dev environment config (AI Search)
│   ├── uat/
│   │   └── config.yml             # UAT environment config (AI Search)
│   └── prod/
│       └── config.yml             # Prod environment config (AI Search)
└── README.md                      # This documentation file
```

---

## Azure Prerequisites & Integration Setup

To run this pipeline successfully, you must configure authentication and permissions between GitHub and Azure.

### 1. Register an App in Microsoft Entra ID (Azure AD)
1. Go to the Azure Portal -> **Microsoft Entra ID** -> **App registrations** -> **New registration**.
2. Give it a descriptive name (e.g., `github-actions-aoai-deployer`) and click **Register**.

### 2. Configure Federated Credentials (OIDC)
Instead of using a client secret, this pipeline uses OpenID Connect (OIDC) to request a temporary token.
1. In your App Registration, go to **Certificates & secrets** -> **Federated credentials** -> **Add credential**.
2. Select **GitHub Actions active workflow** as the federated credential scenario.
3. Provide the repository details:
   - **Organization/Owner**: `prathamesh633` (or your GitHub organization)
   - **Repository**: `Automatic-Model-Deploy-Azure`
   - **Entity type**: Select **Environment**.
   - **GitHub environment name**: Enter the corresponding environment names mapping to your configuration (e.g., `aoai-dev`, `aoai-uat`, `aoai-prod`).
4. Give it a name and click **Add**. Repeat this for each target environment.

### 3. Assign Role Permissions in Azure
The Service Principal needs permission to manage deployments on the Azure OpenAI resources.
1. Navigate to the **Resource Group** or specific **Azure OpenAI Service resource** in the Azure Portal.
2. Go to **Access control (IAM)** -> **Add role assignment**.
3. Select the role **Cognitive Services Contributor** (allows full management of Cognitive Services resource deployments).
4. Assign access to the **User, group, or service principal** and select the registered App/Service Principal you created.

---

## Required Configurations & Variables

### GitHub Secrets
You must configure the following GitHub Secrets at the repository level or environment level (recommended):

| Secret Name | Description | Source in Azure |
| :--- | :--- | :--- |
| `AZURE_CLIENT_ID` | The **Application (client) ID** of the registered Entra ID App. | App Registration -> Overview page |
| `AZURE_TENANT_ID` | The **Directory (tenant) ID** of your Entra ID Tenant. | App Registration -> Overview page or Entra ID Overview |

### Environment Configuration Files
Each environment has its own configuration file located at `env/<environment>/config.yml`. Update these files with your actual Azure resource metadata:

```yaml
github_environment: aoai-dev  # Maps to the GitHub Environment name for OIDC federation and secrets

azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"  # Target Azure Subscription ID
  resource_group: "rg-aoai-dev"                             # Target Resource Group Name
  aoai_resource_name: "aoai-dev"                           # Target Azure OpenAI Service Instance Name

approved_models:
  gpt-4o:
    version: "2024-11-20"
    capacity_tpm: 10          # Default Tokens Per Minute (TPM) capacity in thousands (e.g., 10 = 10,000 TPM)
    scale_type: Standard      # Default Scale Type (Standard, GlobalStandard, ProvisionedManaged)
    capacity_tpm_override: ""
    scale_type_override: ""
  # Add other models as required...
```

---

## How to Run the Pipelines

The pipelines are triggered manually via **Workflow Dispatch** in GitHub.

### 1. Azure OpenAI Model Deployment
1. Navigate to the **Actions** tab in your GitHub repository.
2. Select **Manage Azure OpenAI deployments** from the sidebar.
3. Click the **Run workflow** dropdown on the right.
4. Fill out the input form:
   * **Choose whether to deploy or delete a model deployment**: `deploy` or `delete`
   * **Choose the target environment**: `dev`, `uat`, or `prod`
   * **Approved model to deploy**: Choose one of the approved models (ignored for `delete`)
   * **Deployment name to create or delete**: The custom name for the model deployment in your Azure OpenAI instance (must be 1-64 alphanumeric/hyphen characters)
   * **Capacity TPM override in thousands**: Optional. Overrides the default capacity specified in the environment config.
   * **Scale type override**: Optional. Overrides the default scale type (e.g., `GlobalStandard`).
   * **Required only for delete**: Set to `yes` if you chose `delete` as the action (safety confirmation block).
5. Click **Run workflow**.

### 2. Azure AI Search Service Deployment
1. Navigate to the **Actions** tab in your GitHub repository.
2. Select **Manage Azure AI Search deployments** from the sidebar.
3. Click the **Run workflow** dropdown on the right.
4. Fill out the input form:
   * **Choose whether to deploy or delete AI Search service**: `deploy` or `delete`
   * **Choose the target environment**: `dev`, `uat`, or `prod`
   * **Search service name override**: Optional custom name for the service.
   * **SKU tier override**: Optional pricing tier (e.g., `basic`, `standard`).
   * **Replica count override**: Optional number of replicas.
   * **Partition count override**: Optional number of partitions.
   * **Required only for delete**: Set to `yes` if you chose `delete` as the action (safety confirmation block).
5. Click **Run workflow**.

---

## How the Pipelines Work Under the Hood

### Phase 1: Prepare & Validate (`prepare` job)
* Loads the targeted environment's YAML configuration (from `env/` for OpenAI or `env-2/` for AI Search).
* Validates inputs (such as service naming rules, action configurations, and safety deletion blocks).
* Generates output variables and logs a summarized markdown report to the GitHub Actions workflow run summary.

### Phase 2: Execution (`deploy` or `delete` job)
* **Authentication**: Logs into Azure using the repository's federated identity (`azure/login@v2`).
* **Deployment/Deletion**: Executes the Azure CLI to create or delete the resource/deployment.
  * For OpenAI: `az cognitiveservices account deployment create/delete`.
  * For AI Search: Executes `az search service create/delete` directly.
* **Status Polling**: Polls the Azure resource manager every 15 seconds (for up to 5 minutes) to ensure the operation completes successfully.
* **Post-Execution**: Logs out of the session.

