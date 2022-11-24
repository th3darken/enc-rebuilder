#!/bin/bash

chmod +x /opt/env-rebuilder/env-rebuilder.sh

mkdir -p /usr/local/share/bash-completion/completions
ln -s /opt/env-rebuilder/env-rebuilder.bash /usr/local/share/bash-completion/completions/env-rebuilder.bash

mkdir -p /usr/local/bin
ln -s /opt/env-rebuilder/env-rebuilder.sh /usr/local/bin/env-rebuilder
