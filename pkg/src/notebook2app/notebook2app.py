import os
import pathlib

import jinja2
import kubernetes
import nbformat
import nbconvert


NAMESPACE = pathlib.Path("/var/run/secrets/kubernetes.io/serviceaccount/namespace").read_text().strip()
TEMPLATES_DIR = pathlib.Path(__file__).resolve().parent / "templates"

jinja_env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(TEMPLATES_DIR),
)


def _convert_nb_to_py(
    notebook_file: pathlib.Path,
) -> str:
    notebook_contents = nbformat.read(notebook_file.open(), as_version=4)
    exporter = nbconvert.PythonExporter()
    py_file_content, _ = exporter.from_notebook_node(notebook_contents)
    return py_file_content


def _render_template(
    app_name          : str,
    command           : str,
    base_url          : str,
    notebook_file     : pathlib.Path,
    requirements_file : pathlib.Path,
    output_file       : pathlib.Path,
) -> None:

    template = jinja_env.get_template(f"app.yaml.j2")

    output_file.write_text(template.render(
        app_name          = app_name,
        command           = command,
        base_url          = base_url,
        namespace         = NAMESPACE,
        app_file          = _convert_nb_to_py(notebook_file),
        requirements_file = requirements_file.read_text(),
    ))


def _get_src_dir() -> None:
    if "JPY_SESSION_NAME" not in os.environ:
        err_msg = (
            "Could not find the environment variable 'JPY_SESSION_NAME'. "
            "The 'JPY_SESSION_NAME' environment variable defines the current "
            "notebook's file path. Only call notebook2app.deploy() from a "
            "notebook during a JupyterHub session."
        )

        raise Exception(err_msg)
    
    return pathlib.Path(os.environ["JPY_SESSION_NAME"]).parent


def deploy(
    name              : str,
    notebook_file     : str,
    requirements_file : str,
    command           : str  = "python app.py",
    dry_run           : bool = False,
) -> None:
    src_dir = _get_src_dir()
    notebook_file = src_dir / notebook_file
    requirements_file = src_dir / requirements_file
    
    if not notebook_file.is_file():
        err_msg = (
            f"Could not find the provided 'notebook_file' at '{notebook_file}'. "
            "Ensure that the file path provided to 'notebook_file' is relative "
            f"to the directory containing your deploy notebook ({src_dir})."
        )
        
        raise FileNotFoundError(err_msg)

    if not requirements_file.is_file():
        err_msg = (
            f"Could not find the provided 'requirements_file' at "
            "'{requirements_file}'. Ensure that the file path provided to "
            "'requirements_file' is relative to the directory containing your "
            f"deploy notebook ({src_dir})."
        )
        
        raise FileNotFoundError(err_msg)

    if "JUPYTERHUB_USER" not in os.environ:
        err_msg = (
            "Could not find the environment variable 'JUPYTERHUB_USER'. "
            "The 'JUPYTERHUB_USER' environment variable defines the current "
            "user's name. Only call notebook2app.deploy() from a notebook "
            "during a JupyterHub session."
        )
        
        raise FileNotFoundError(err_msg)
    
    if "NOTEBOOK2APP_BASE_URL" not in os.environ:
        err_msg = (
            "Could not find the environment variable 'NOTEBOOK2APP_BASE_URL'. "
            "Your cluster forgot to define it... oof..."
        )
        
        raise FileNotFoundError(err_msg)

    app_name = f"{name}-{os.environ["JUPYTERHUB_USER"]}"
    base_url = os.environ["NOTEBOOK2APP_BASE_URL"]
    output_file = src_dir / f"{app_name}.yaml"

    output_file.unlink(missing_ok=True)
    
    _render_template(
        app_name,
        command,
        base_url,
        notebook_file,
        requirements_file,
        output_file,
    )

    if not dry_run:
        kubernetes.config.load_incluster_config()

        kubernetes.utils.create_from_yaml(
            kubernetes.client.ApiClient(),
            yaml_file=str(output_file),
            verbose=True,
            namespace=NAMESPACE,
            apply=True,
            timeout_seconds=30,
            pretty=True,
        )

    
