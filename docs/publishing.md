# Publishing

Local release checks:

```bash
python3 -m unittest discover -s tests
python3 -m py_compile multiplexor/*.py tests/*.py
multiplexor --version
```

GitHub upload:

```bash
git add .
git commit -m "Prepare multiplexor v1"
git remote add origin git@github.com:<owner>/multiplexor.git
git push -u origin main
```

If the default branch is `master`, push that branch instead.
