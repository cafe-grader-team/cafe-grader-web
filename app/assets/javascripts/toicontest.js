var TOIContest = {
    NO_TIMEOUT: -1,
    
    timeOuts: {},
    
    problemSelectClick: function() {
        $$(".submission-submit-divs").each(function(item) {
            item.hide();
        });
        var problem_id = $('submission_problem_id').value;
        if ( problem_id < 0 ) {
            return;
        }
        $("submission_submit_div_" + problem_id + "_id").show();
    },

    confirmDownload: function() {
        return confirm("แน่ใจ?");
    },

    refreshTimeOutMessages: function() {
        for ( var pid in TOIContest.timeOuts ) {
            var timeOut = TOIContest.timeOuts[ pid ];
            if ( timeOut != TOIContest.NO_TIMEOUT ) {
                if ( timeOut > 0 ) {
                    var minLeft = parseInt(timeOut / 60);
                    var secLeft = parseInt(timeOut % 60);
                    $('submission_time_left_' + pid + '_id').innerHTML = '| <b>เหลือเวลาอีก ' + minLeft + ':' + secLeft + ' นาที</b>';
                } else {
                    $('submission_time_left_' + pid + '_id').innerHTML = '| <b>หมดเวลาส่ง</a>';
                    $('submission_form_'+ pid + '_id').hide();
                }
            }
        }
    }
};

