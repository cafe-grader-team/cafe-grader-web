var CodejomTimeout = {

    timeStarted: null,

    inputDataDuration: 5,  // 5 minutes

    timeouts: [],

    updateProblemMessages: function() {
	CodejomTimeout.timeouts.each(function(data) {
	    if(data.timeout==null) {
		$("problem-submission-form-" + data.problem).hide();
	    } else if(data.timeout==0) {
		$("problem-timing-message-" + data.problem).innerHTML = 
		    "The recent input data is expired.  Please download a new one.  You'll have 5 minute to submit.";
		$("problem-submission-form-" + data.problem).hide();
	    } else {
		$("problem-timing-message-" + data.problem).innerHTML = 
		    "You have about " + parseInt(data.timeout/60) + " minute(s) and " + parseInt(data.timeout % 60) + " second(s) to submit.";
		$("problem-submission-form-" + data.problem).show();
	    }
	});
    },

    refreshProblemMessages: function() {
	var timeElapsed = ((new Date()).getTime() - CodejomTimeout.timeStarted)/1000;
	// update timeout info
	CodejomTimeout.timeouts.each(function(data) {
	    if(data.timeout > timeElapsed) {
		data.timeout -= timeElapsed;
	    } else if(data.timeout > 0) {
		data.timeout = 0;
	    }
	});	

	CodejomTimeout.updateProblemMessages();
	CodejomTimeout.registerRefreshEvent();
    },

    registerRefreshEvent: function() {
	CodejomTimeout.timeStarted = (new Date()).getTime(),
	setTimeout(function () {
	    CodejomTimeout.refreshProblemMessages();
	}, 2700);
    },

    updateTimeoutAfterDownloadClick: function(problem) {
	CodejomTimeout.timeouts
	    .filter(function(data) { return data.problem==problem; })
	    .each(function(data) {
		if(data.timeout==0 || data.timeout==null) {
		    // TODO: use value from rails app.
		    data.timeout = CodejomTimeout.inputDataDuration * 60;  
		}
	    });
	CodejomTimeout.updateProblemMessages();
    },
};
