function updateSiteList() {
    currentCountry = document.getElementById("site_country_id").value;

    sites = siteList[currentCountry];
    siteSelect = document.getElementById("login_site_id");
    old_len = siteSelect.length;
    // clear old box
    for(i=0; i<old_len; i++) siteSelect.remove(0);
    
    if(currentCountry==0) {
	for(i=0; i<allSiteList.length; i++) {
	    if(allSiteList[i]!=null) {
		try {
		    siteSelect.add(new Option(allSiteList[i],""+i,false,false),null);
		} catch(ex) {
		    siteSelect.add(new Option(allSiteList[i],""+i,false,false));
		}
	    }
	}
    } else {
	for(i=0; i<sites.length; i++) {
	    if(sites[i]!=null) {
		try {
		    siteSelect.add(new Option(sites[i],""+i,false,false),null);
		} catch(ex) {
		    siteSelect.add(new Option(sites[i],""+i,false,false));
		}
	    }
	}
    }
}
 