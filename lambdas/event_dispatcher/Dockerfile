FROM public.ecr.aws/lambda/python:3.12-arm64

COPY requirements.txt ${LAMBDA_TASK_ROOT}

RUN pip install -r requirements.txt

COPY lambda_function.py ${LAMBDA_TASK_ROOT}

ADD utils ${LAMBDA_TASK_ROOT}/utils

CMD ["lambda_function.handler"]
