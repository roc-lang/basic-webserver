import Host

## Pause the current synchronous Roc handler or lifecycle hook.
##
## Sleeping occupies one bounded Roc execution slot, so it should not be used
## to wait indefinitely or to implement background scheduling.
Sleep := [].{

	## Sleep for at least the given number of milliseconds.
	millis! : U64 => {}
	millis! = |milliseconds| Host.sleep_millis!(milliseconds)
}
