# Deploying a Flask API

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