# sbpanel 0.0.3

Starbound web status panel! Parses the server debug log to show connected players, active worlds and chat history. Can be observed here: [starbound.mispy.me](http://starbound.mispy.me/)

Thanks to [@collettiquette](http://twitter.com/collettiquette) for the idea!

## Installation

Requires [Ruby 1.9.3+](https://www.ruby-lang.org/en/). Since it relies on [fuser](https://en.wikipedia.org/wiki/Fuser_\(Unix\)) to find the Starbound process, probably UNIX systems only for the moment.

```bash
gem install sbpanel
```

## Usage

```
Usage: sbpanel [options] STARBOUND_LOG_PATH
    -b, --bind ADDR                  Address to bind [0.0.0.0]
    -p, --port PORT                  Port to bind [8000]
    -a, --address ADDR               Server address to display [hostname]
    -h, --help                       Display this screen
```
