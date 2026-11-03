# Share sprout

Ready-to-post announcements in English and Spanish. Copy, paste, adjust the tone.

- Repo: https://github.com/beenjii14/sprout
- Site: https://beenjii14.github.io/sprout/
- Social card: [`docs/assets/social-preview.png`](assets/social-preview.png)

> Only Claude Code is tested end to end. Gemini CLI, Codex, GitHub Copilot CLI and Cursor follow each tool's documented
> non-interactive mode; anything else works through `SPROUT_AI_CMD`.

---

## 🇬🇧 English

### Slack (team)

```text
🌱 I built a small tool so we stop thinking about branch names: *sprout*.

Run `sprout PROJ-1234` and it:
• reads the ticket from Jira
• builds a short, descriptive name (`PROJ-1234/feat-login-sso-okta`), in English by default
• switches to the base branch, pulls, and creates the branch

It uses the AI you already have in your terminal: Claude Code, Gemini CLI, Codex, GitHub Copilot CLI or Cursor. You can also point it at any command, for example a local model with Ollama. With none installed it uses a local rule and works the same.

Need another base just this once? `sprout PROJ-1234 --base develop`. Works with any Jira Cloud project and it is open source.

Install (macOS): `brew tap beenjii14/tap && brew trust beenjii14/tap && brew install sprout`, then `sprout-setup`.
Docs: https://beenjii14.github.io/sprout/
Found something to improve? Open an issue or a PR 🙌
```

### LinkedIn

```text
I just published my first open source tool: sprout 🌱

Every ticket started the same way: copy the Jira title, invent a branch name, git switch, git pull, git switch -c. I automated it with one command:

sprout PROJ-142 → PROJ-142/feat-sso-login-okta-admin

It reads the Jira ticket, writes a short descriptive name and creates the branch. What mattered most to me was not locking anyone into a vendor:
• it uses the AI you already have in your terminal (Claude Code, Gemini CLI, Codex, GitHub Copilot CLI, Cursor) or any command you configure, even a local model
• without AI, a local rule does the job
• consistent names across the whole team, without leaving the terminal
• options like --base and --no-pull for one-off cases
• installs with Homebrew and has a documentation site

Built in zsh, MIT licensed, contributions welcome.

🔗 https://github.com/beenjii14/sprout
🌐 https://beenjii14.github.io/sprout/

If you work with Jira and Git, I would love to hear what you would add.

#OpenSource #Git #Jira #DeveloperTools #Productivity
```

### X

```text
🌱 sprout: one command reads your Jira ticket and creates the Git branch with a short, descriptive name.

sprout PROJ-142 → PROJ-142/feat-sso-login-okta-admin

Uses your terminal's AI (Claude, Gemini, Codex, Copilot, Cursor) or none. zsh, MIT.
https://github.com/beenjii14/sprout
```

---

## 🇪🇸 Español

### Slack (equipo)

```text
🌱 Armé una herramienta para dejar de pensar nombres de ramas: *sprout*.

Corrés `sprout PROJ-1234` y hace todo:
• lee el ticket de Jira
• arma un nombre corto y descriptivo (`PROJ-1234/feat-login-sso-okta`), en inglés por defecto
• hace `switch` a la base, `pull` y crea la rama

Usa la IA que ya tengas en la terminal: Claude Code, Gemini CLI, Codex, GitHub Copilot CLI o Cursor. También podés apuntarlo a cualquier comando, por ejemplo un modelo local con Ollama. Si no tenés ninguna, usa una regla local y funciona igual.

¿Necesitás otra base solo esta vez? `sprout PROJ-1234 --base develop`. Funciona con cualquier proyecto de Jira Cloud y es de código abierto.

Instalar (macOS): `brew tap beenjii14/tap && brew trust beenjii14/tap && brew install sprout`, y después `sprout-setup`.
Docs: https://beenjii14.github.io/sprout/
Si le encontrás algo mejorable, abrí un issue o un PR 🙌
```

### LinkedIn

```text
Publiqué mi primera herramienta open source: sprout 🌱

Cada ticket empezaba igual: copiar el título de Jira, inventar un nombre de rama, git switch, git pull, git switch -c. Lo automaticé con un solo comando:

sprout PROJ-142 → PROJ-142/feat-sso-login-okta-admin

Lee el ticket de Jira, genera un nombre corto y descriptivo y crea la rama. Lo que más me importaba era que no te ate a un proveedor:
• usa la IA que ya tengas en la terminal (Claude Code, Gemini CLI, Codex, GitHub Copilot CLI, Cursor) o cualquier comando que configures, incluso un modelo local
• sin IA, una regla local hace el trabajo
• nombres consistentes en todo el equipo, sin salir de la terminal
• opciones como --base y --no-pull para casos puntuales
• se instala con Homebrew y tiene una web con documentación

Está hecho en zsh, es MIT y acepta contribuciones.

🔗 https://github.com/beenjii14/sprout
🌐 https://beenjii14.github.io/sprout/

Si trabajás con Jira y Git, me encantaría saber qué le agregarías.

#OpenSource #Git #Jira #DeveloperTools #Productividad
```

### X

```text
🌱 sprout: un comando lee tu ticket de Jira y crea la rama de Git con un nombre corto y descriptivo.

sprout PROJ-142 → PROJ-142/feat-sso-login-okta-admin

Usa la IA de tu terminal (Claude, Gemini, Codex, Copilot, Cursor) o ninguna. zsh, MIT.
https://github.com/beenjii14/sprout
```
