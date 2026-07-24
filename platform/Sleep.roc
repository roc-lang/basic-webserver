import Host

Sleep := [].{

	## Sleep for at least the given number of milliseconds.
	millis! : U64 => {}
	millis! = |milliseconds| Host.sleep_millis!(milliseconds)
}
