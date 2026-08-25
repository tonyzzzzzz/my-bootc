# Secure Boot

The NVIDIA kernel modules are built out of tree via DKMS, so the kernel will not
load them under Secure Boot unless they are signed by a key the firmware trusts.
This image signs them with a **MOK** (Machine Owner Key) that you generate once
and enroll on the machine.

Fedora's kernel itself is already signed by a key that shim trusts. Only the
out-of-tree NVIDIA modules need your key.

## One-time setup

### 1. Generate the key pair

```sh
just mok-keygen
```

Produces:

| File | Secret? | Goes where |
| --- | --- | --- |
| `secureboot/mok.key` | **yes** | GitHub Actions secret. Gitignored. |
| `secureboot/mok.der` | no | Committed to the repo, shipped in the image. |

Regenerating the key means re-enrolling it on every machine, so `mok-keygen`
refuses to overwrite an existing key.

### 2. Give the private key to CI

```sh
gh secret set MOK_PRIVATE_KEY < secureboot/mok.key
```

The build fails loudly if this secret is missing, rather than silently shipping
unsigned modules and leaving you unable to boot with Secure Boot on.

### 3. Commit the certificate

```sh
git add secureboot/mok.der && git commit -m "add secure boot signing certificate"
```

## Enrolling on the machine

**Order matters.** Enroll the key *before* turning Secure Boot on, and only
after you are running an image built with signing enabled. Turning Secure Boot
on first will leave the GPU without a driver.

### 1. Boot the signed image

Rebase (or reboot into) an image built after signing was enabled, then confirm
the modules really are signed:

```sh
modinfo nvidia | grep -E 'sig_id|signer'
```

You should see your certificate's CN as the signer. If there is no output, the
image was built without the key — do not continue.

### 2. Import the key

```sh
sudo mokutil --import /usr/share/secureboot/mok.der
```

You will be prompted for a one-time password. It is only used at the next boot,
so pick something you can type on a US keyboard layout in the firmware UI.

### 3. Reboot and enroll

On reboot, **MokManager** appears (a blue text-mode screen). It only appears
once — if you boot straight to the login screen, the import did not register.

- `Enroll MOK` → `Continue` → `Yes`
- Enter the password from step 2
- `Reboot`

### 4. Verify enrollment

```sh
mokutil --test-key /usr/share/secureboot/mok.der   # "is already enrolled"
mokutil --list-enrolled | grep -A1 'module signing'
```

### 5. Turn on Secure Boot

Reboot into UEFI firmware setup and enable Secure Boot. On ASUS boards this is
usually under `Boot` → `Secure Boot` → `OS Type: Windows UEFI mode`; you may
need to leave Setup Mode or clear/restore factory keys first.

### 6. Confirm

```sh
mokutil --sb-state          # SecureBoot enabled
nvidia-smi                  # driver is loaded
dmesg | grep -i 'module verification'
```

If `nvidia-smi` fails while Secure Boot is on, the module was rejected. Boot
with Secure Boot off and recheck steps 1 and 4.

## Notes

- **Key rotation.** Replacing the key means re-enrolling on every machine. The
  certificate is generated with a 100-year validity so this is not something you
  need to do on a schedule.
- **Key compromise.** Anyone with `mok.key` can sign a kernel module your
  machine will load with full kernel privileges. Treat it like an SSH host key.
  If it leaks, generate a new pair, `mokutil --delete` the old certificate, and
  re-enroll.
- **The private key never enters the image.** It is passed to `podman build` as
  a `--secret`, which mounts it on tmpfs for one `RUN` step. `nvidia.sh` also
  removes `/var/lib/dkms` afterwards so no cached copy survives.
- **Local builds.** `just build` picks up `secureboot/mok.key` automatically if
  it exists. Without it the build still succeeds, but modules are unsigned and
  `just verify` will report that.
