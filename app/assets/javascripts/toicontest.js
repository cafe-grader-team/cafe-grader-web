var TOIContest = {
    NO_TIMEOUT: -1,
    SUBMISSION_TIMEOUT: 300,
    
    timeOuts: {},
    timeStarted: 0,
    
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

    confirmDownload: function(pid) {
        result = confirm("คุณแน่ใจที่จะส่งข้อนี้หรือไม่?\nเมื่อคุณดาวน์โหลดข้อมูลชุดทดสอบแล้ว คุณจะต้องส่งข้อมูลส่งออกและโปรแกรมภายในเวลา 5 นาที");
        if ( result ) {
            if ( TOIContest.timeOuts[ pid ] == TOIContest.NO_TIMEOUT ) {
                TOIContest.refreshTimeOuts();

                TOIContest.timeOuts[ pid ] = TOIContest.SUBMISSION_TIMEOUT;

                TOIContest.refreshTimeOutMessages();
            }
        }
        return result;
    },

    refreshTimeOutMessages: function() {
        for ( var pid in TOIContest.timeOuts ) {
            var timeOut = TOIContest.timeOuts[ pid ];
            if ( timeOut != TOIContest.NO_TIMEOUT ) {
                if ( timeOut > 0 ) {
                    var minLeft = parseInt(timeOut / 60);
                    var secLeft = parseInt(timeOut % 60);
                    $('submission_time_left_' + pid + '_id').innerHTML = '| <b>เหลือเวลาอีก ' + minLeft + ':' + secLeft + ' นาที</b>';
                    $('submission_form_'+ pid + '_id').show();
                } else {
                    $('submission_time_left_' + pid + '_id').innerHTML = '| <b>หมดเวลาส่ง</a>';
                    $('submission_form_'+ pid + '_id').hide();
                }
            } else {
                $('submission_form_'+ pid + '_id').hide();
            }
        }
    },

    refreshTimeOuts: function() {
        if ( TOIContest.timeStarted == 0 ) {
            TOIContest.timeStarted = (new Date()).getTime();
        }
        
        var timeElapsed = ((new Date()).getTime() - TOIContest.timeStarted)/1000;
        for ( var pid in TOIContest.timeOuts ) {
            var timeOut = TOIContest.timeOuts[ pid ];
            if ( timeOut > timeElapsed ) {
                TOIContest.timeOuts[ pid ] -= timeElapsed;
            } else if ( timeOut > 0 ) {
                TOIContest.timeOuts[ pid ] = 0;
            }
        }
    },
    
    registerRefreshEvent: function() {
        TOIContest.timeStarted = (new Date()).getTime();
        setTimeout(function () {
            TOIContest.refreshTimeOuts();
            TOIContest.refreshTimeOutMessages();
            TOIContest.registerRefreshEvent();
        }, 1000);
    },
};

