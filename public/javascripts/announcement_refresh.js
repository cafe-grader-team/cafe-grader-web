
var Announcement = {

    mostRecentId: 0,

    setMostRecentId: function(id) {
	Announcement.mostRecentId = id;
    },

    updateRecentId: function(id) {
	if(Announcement.mostRecentId < id)
	    Announcement.mostRecentId = id;
    },

    refreshAnnouncement: function() {
	var url = '/main/announcements';
	new Ajax.Request(url, {
	    method: 'get',
	    parameters: { recent: Announcement.mostRecentId },
	    onSuccess: function(transport) {
		if(transport.responseText.match(/\S/)!=null) {
 		    var announcementBody = $("announcementbox-body");
		    announcementBody.insert({ top: transport.responseText });
		    var announcementBoxes = $$(".announcementbox");
		    if(announcementBoxes.length!=0)
			announcementBoxes[0].show();
		}
	    }
	});
	Announcement.registerRefreshEventTimer();
    },

    registerRefreshEventTimer: function() {
	setTimeout(function () {
	    Announcement.refreshAnnouncement();
	}, 30000);
    }
};
