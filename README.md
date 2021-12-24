# Deploying a Flask API

 External IP

This is the project starter repo for the course Server Deployment, Containerization, and Testing.

In this project you will containerize and deploy a Flask API to a Kubernetes cluster using Docker, AWS EKS, CodePipeline, and CodeBuild.

The Flask app that will be used for this project consists of a simple API with three endpoints:

- `GET '/'`: This is a simple health check, which returns the response 'Healthy'. 
- `POST '/auth'`: This takes a email and password as json arguments and returns a JWT based on a custom secret.
- `GET '/contents'`: This requires a valid JWT, and returns the un-encrpyted contents of that token. 

The app relies on a secret set as the environment variable `JWT_SECRET` to produce a JWT. The built-in Flask server is adequate for local development, but not production, so you will be using the production-ready [Gunicorn](https://gunicorn.org/) server when deploying the app.

## Initial setup
1. Fork this project to your Github account.
2. Locally clone your forked version to begin working on the project.

## Dependencies

- Docker Engine
    - Installation instructions for all OSes can be found [here](https://docs.docker.com/install/).
    - For Mac users, if you have no previous Docker Toolbox installation, you can install Docker Desktop for Mac. If you already have a Docker Toolbox installation, please read [this](https://docs.docker.com/docker-for-mac/docker-toolbox/) before installing.
 - AWS Account
     - You can create an AWS account by signing up [here](https://aws.amazon.com/#).
     
## Project Steps

Completing the project involves several steps:

1. Write a Dockerfile for a simple Flask API
2. Build and test the container locally
3. Create an EKS cluster
4. Store a secret using AWS Parameter Store
5. Create a CodePipeline pipeline triggered by GitHub checkins
6. Create a CodeBuild stage which will build, test, and deploy your code

For more detail about each of these steps, see the project lesson.

## Testing Locally

Install command-line JSON parser:
```
sudo apt-get install jq
```

Create a new virtual environment:
```
python3 -m virtualenv fsndp4
```

Activate the environment:
```
source fsndp4/bin/activate
```

Install the pip dependencies
```
pip install -r requirements.txt
```

Export environment variables
```
export JWT_SECRET='myjwtsecret'
export LOG_LEVEL=DEBUG
# Verify
echo $JWT_SECRET
echo $LOG_LEVEL
```

Run the Flask App
```
python main.py
```

Open http://127.0.0.1:8080/ in a browser or run the following in a terminal:
```
curl --request GET http://localhost:8080/
```

Access endpoint /auth
```
export TOKEN=`curl --data '{"email":"abc@xyz.com","password":"mypwd"}' --header "Content-Type: application/json" -X POST localhost:8080/auth  | jq -r '.token'`
```

To see the JWT token, run:
```
echo $TOKEN
```

Access endpoint /contents
```
curl --request GET 'http://localhost:8080/contents' -H "Authorization: Bearer ${TOKEN}" | jq .
```

## Build Dockerfile

Build the dockerfile by running the following in the project's root directory:
```
docker build -t fsndp4 .
# Check the list of images
docker image ls
# Remove any image
docker image rm <image_id>
```

Create and run a container using the image locally
```
docker run --name fsndp4Container --env-file=.env_file -p 8081:8080 fsndp4
# List running containers
docker container ls
docker ps
# Stop a container
docker container stop <container_id>
# Remove a container
docker container rm <container_id>
```

Check the endpoints
```
# Flask server running inside a container
curl --request GET 'http://localhost:8081/'
# Flask server running locally (only the port number is different)
curl --request GET 'http://localhost:8080/'
```
or check http://localhost:8081/ in the browser. You should see a "Healthy" response.

Try running the following commands for the other two endpoints:
```
# Calls the endpoint 'localhost:8081/auth' with the email/password as the message body. 
# The return JWT token assigned to the environment variable 'TOKEN' 
export TOKEN=`curl --data '{"email":"abc@xyz.com","password":"WindowsPwd"}' --header "Content-Type: application/json" -X POST localhost:8081/auth  | jq -r '.token'`
echo $TOKEN
# Decrypt the token and returns its content
curl --request GET 'http://localhost:8081/contents' -H "Authorization: Bearer ${TOKEN}" | jq .
```

## Create IAM Role

Get your AWS account id:
```
aws sts get-caller-identity --query Account --output text
```

Create a trust relationship. To do this, create a blank trust.json file, and add the following content to it:
```
{
 "Version": "2012-10-17",
 "Statement": [
     {
         "Effect": "Allow",
         "Principal": {
             "AWS": "arn:aws:iam::<ACCOUNT_ID>:root"
         },
         "Action": "sts:AssumeRole"
     }
 ]
}
```
Replace the `<ACCOUNT_ID>` with your actual account Id. This policy file defines the actions allowed by whosoever assumes the new Role. 

Create a role, 'UdacityFlaskDeployCBKubectlRole', using the trust.json trust relationship:
```
aws iam create-role --role-name UdacityFlaskDeployCBKubectlRole --assume-role-policy-document file://trust.json --output text --query 'Role.Arn'
```

Create a policy document, iam-role-policy.json, that allows (whosoever assumes the role) to perform specific actions (permissions) - "eks:Describe*" and "ssm:GetParameters" as:
```
{
 "Version": "2012-10-17",
 "Statement":[{
     "Effect": "Allow",
     "Action": ["eks:Describe*", "ssm:GetParameters"],
     "Resource":"*"
 }]
}
```

Attach the iam-role-policy.json policy to the 'UdacityFlaskDeployCBKubectlRole' as:
```
aws iam put-role-policy --role-name UdacityFlaskDeployCBKubectlRole --policy-name eks-describe --policy-document file://iam-role-policy.json
```

## Create EKS Cluster

Create an EKS cluster named “simple-jwt-api” in a region of your choice:
```
# Create cluster in the default region
eksctl create cluster --name simple-jwt-api
# Create a cluster in a specific region, such as ap-southeast-1
eksctl create cluster --name simple-jwt-api --region=ap-southeast-1
```

You can go to the CloudFormation or EKS web-console to view the progress. If you don’t see any progress, be sure that you are viewing clusters in the same region that they are being created. Once the status is CREATE_COMPLETE in your command line, check the health of your clusters nodes: 
```
kubectl get nodes
```

Remember, in case you wish to delete the cluster, you can do it using either way:
- CloudFormation console - select your stack and choose delete from the actions menu, or
- AWSCLI - delete using eksctl:
```
# For example, the region you have used is ap-southeast-1
eksctl delete cluster simple-jwt-api  --region=ap-southeast-1
```

## Allowing the new role access to the cluster

Get the current configmap and save it to a file:
```
# Mac/Linux
# The file will be created at `/System/Volumes/Data/private/tmp/aws-auth-patch.yml` path
kubectl get -n kube-system configmap/aws-auth -o yaml > /tmp/aws-auth-patch.yml
# Windows 
# The file will be created in the current working directory
kubectl get -n kube-system configmap/aws-auth -o yaml > aws-auth-patch.yml

# Modified to save in current directory
kubectl get -n kube-system configmap/aws-auth -o yaml > aws-auth-patch.yml
```

Open the aws-auth-patch.yml file using any editor, such as VS code editor:
```
# Mac/Linux
code /System/Volumes/Data/private/tmp/aws-auth-patch.yml
# Windows
code aws-auth-patch.yml
```

Add the following group in the data → mapRoles section of this file.
```
mapRoles: |
 - groups:
   - system:masters
   rolearn: arn:aws:iam::<ACCOUNT_ID>:role/UdacityFlaskDeployCBKubectlRole
   username: build      
```

Update your cluster's configmap:
```
# Mac/Linux
kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"
# Windows
kubectl patch configmap/aws-auth -n kube-system --patch "$(cat aws-auth-patch.yml)"

# Modified for local directory
kubectl patch configmap/aws-auth -n kube-system --patch "$(cat ./aws-auth-patch.yml)"
```

In case of the following error:
```
Error from server (Conflict): Operation cannot be fulfilled on configmaps "aws-auth": the object has been modified; please apply your changes to the latest version and try again
```
Re-run the above three steps beginning from the kubectl get command.


## Generate GitHub access token

Generate a token [here](https://github.com/settings/tokens/), with full control of private repositories


## Create a pipeline using CloudFormation template

Modify the template file `ci-cd-codepipeline.cfn.yml` that you will use to create your CodePipeline pipeline and CodeBuild project

| Parameter | Field | Possible Value |
| --------- | ----- | -------------- |
| EksClusterName | Default | simple-jwt-api <br /> Name of the EKS cluster you created |
| GitSourceRepo | Default | FSND-Deploy-Flask-App-to-Kubernetes-Using-EKS <br /> Github repo name |
| GitBranch | Default | master <br /> Or any other you want to link to the Pipeline |
| GitHubUser | Default | Your Github username |
| KubectlRoleName | Default | UdacityFlaskDeployCBKubectlRole <br /> We created this role earlier |


Use the AWS web-console to create a stack for CodePipeline using the CloudFormation template file ci-cd-codepipeline.cfn.yml. Go to the CloudFormation service in the AWS console. Press the Create Stack button. It will make you go through the following three steps -

    Step 1 - Specify template - Choose the options "Template is ready" and "Upload a template file" to upload the template file ci-cd-codepipeline.cfn.yml. Click the 'Next' button.

    Step 2 - Specify stack details - Give the stack a name, fill in your GitHub login, and the Github access token generated in the previous step. Make sure that the cluster name matches the one you have created, and the 'kubectl IAM role' matches the role you created above, and the repository matches the name of your forked repo.

    Step 3 - Configure stack options - Leave default, and create the stack.

    Troubleshoot: If there is an indentation error in your YAML template file, the CloudFormation will raise a "Template format error". In such a case, you will have to identify the line of error in the template, using any external tools, such as - YAML Validator or YAML Lint.


## Set a Secret using AWS Parameter Store

Add the following to the end of the buildspec.yml file:
```
env:
  parameter-store:         
    JWT_SECRET: JWT_SECRET
```

Put secret into AWS Parameter Store :
```
aws ssm put-parameter --name JWT_SECRET --overwrite --value "YourJWTSecret" --type SecureString
```

Once you submit your project and receive the reviews, you can consider deleting the variable from parameter-store using:
```
aws ssm delete-parameter --name JWT_SECRET
```


## Resolve the "error: You must be logged in to the server (Unauthorized)"

https://aws.amazon.com/premiumsupport/knowledge-center/eks-api-server-unauthorized-error/

To see the configuration of your AWS CLI user or role, run the following command:
```
aws sts get-caller-identity
```

The output returns the Amazon Resource Name (ARN) of the AWS Identity and Access Management (IAM) user or role. For example:
```
{
    "UserId": "XXXXXXXXXXXXXXXXXXXXX",
    "Account": "XXXXXXXXXXXX",
    "Arn": "arn:aws:iam::XXXXXXXXXXXX:user/testuser"
}
```

Confirm that the ARN matches the cluster creator.

Update or generate the kubeconfig file using one of the following commands.

As the IAM user, run the following command:
```
$ aws eks update-kubeconfig --name eks-cluster-name --region aws-region
```

Note: Replace eks-cluster-name with your cluster name. Replace aws-region with your AWS Region.
```
$ aws eks update-kubeconfig --name simple-jwt-api --region ap-southeast-1
```

As the IAM role, run the following command:
```
$ aws eks update-kubeconfig --name eks-cluster-name --region aws-region --role-arn arn:aws:iam::XXXXXXXXXXXX:role/testrole
```

Note: Replace eks-cluster-name with your cluster name. Replace aws-region with your AWS Region.
```
$ aws eks update-kubeconfig --name simple-jwt-api --region ap-southeast-1 --role-arn arn:aws:iam::766155929240:role/UdacityFlaskDeployCBKubectlRole
```

To confirm that the kubeconfig file is updated, run the following command:
```
$ kubectl config view --minify
```

To confirm that your IAM user or role is authenticated, run the following command:
```
$ kubectl get svc
```

The output should be similar to the following:
```
NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
kubernetes      ClusterIP   10.100.0.1     <none>        443/TCP   77d

```

If encounter error: You must be logged in to the server (Unauthorized)
```
aws --version

aws eks --region ap-southeast-1 update-kubeconfig --name simple-jwt-api
```

## Test API Endpoints

Get the external IP for your service:
```
kubectl get services simple-jwt-api -o wide
```

Use the external IP url to test the app:
```
export TOKEN=`curl -d '{"email":"<EMAIL>","password":"<PASSWORD>"}' -H "Content-Type: application/json" -X POST <EXTERNAL-IP URL>/auth  | jq -r '.token'`
curl --request GET '<EXTERNAL-IP URL>/contents' -H "Authorization: Bearer ${TOKEN}" | jq 
```