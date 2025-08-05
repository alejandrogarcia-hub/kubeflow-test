# PROMPT

I want build an end-to-end prototype of a pipeline, and the MAIN GOAL is to demonstrate the use of Kubeflow.\
I have ZERO knowledge of Kubeflow, so I need you to help me with the research and the implementation. however, I have knowledge in ML and MLOps.
\
The pipeline will be used to:\
\

- train a model on a dataset using notebooks\
- evaluate the model\
- deploy the model, as a REST API using FastAPI\
- monitor the data and model drift\
- monitor the model performance\
- model registry\
- use Kubeflow to run the pipeline\
\
ULTRA RESEARCH kubeflow, and the best practices for building a pipeline. Here are some links:\
- <https://www.kubeflow.org/docs/started/introduction\>\
- <https://www.kubeflow.org/docs/started/installing-kubeflow/#kubeflow-projects\>\
- <https://www.kubeflow.org/docs/started/architecture\>\
- <https://www.kubeflow.org/docs/components/notebooks\>\
- <https://www.kubeflow.org/docs/components/trainer\>\
- <https://www.kubeflow.org/docs/components/kserve\>\
- <https://github.com/kubeflow\>\
- <https://www.kubeflow.org/docs/components/model-registry\>\
\
For the ML model and DATASET, you can use a well-known and simple model and dataset.\
Write the notebooks and serving code in a way that is easy to understand and follow. COMMENT AND EXPLAIN THE CODE.\
To make it esier to implement and validate, always write a python script and then convert it to a notebook.\
I would like to use the notebooks to train the model, and then use the serving code to deploy the model. It seems Kubeflow is a good fit for this, but I need to understand how to use it.\
\
This computer is running Kubernetes, via the desktop app, and is a Macbookpro intel x86_64.\
\
DEEP ANALYSIS OF THE PROBLEM AND THE SOLUTION, ULTRA RESEARCH for the best practices, examples and documentation.\
Run your research by me before implementing the solution.

## Pipeline

The pipeline will be used to train a model on a dataset.

## Dataset

The dataset is a csv file with the following columns:
