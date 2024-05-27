document.getElementById('ssp-dropdown').addEventListener('change', function() {
    updateDashboard(this.value);
});

function updateDashboard(ssp) {
    // Map each statType to its corresponding nth-child position
    const selectors = {
        openVulnerabilities: '.cards-wrapper .card:nth-child(1) p',
        assignedFindings: '.cards-wrapper .card:nth-child(2) p',
        resolvedThisMonth: '.cards-wrapper .card:nth-child(3) p',
        myPoams: '.cards-wrapper .card:nth-child(4) p',
        totalAssets: '.cards-wrapper .card:nth-child(5) p',
    };

    Object.entries(selectors).forEach(([statType, selector]) => {
        fetchStatsAndUpdateCard(ssp, statType, selector);
    });
}

function fetchStatsAndUpdateCard(ssp, statType, selector) {
    const url = ssp === 'ALL' ? `/api/stats/${statType}` : `/api/stats/${statType}?ssp=${ssp}`;
    fetch(url)
        .then(response => response.json())
        .then(data => {
            document.querySelector(selector).textContent = data.count;
        })
        .catch(error => console.error('Error fetching data for', statType, ':', error));
}

// Assuming the page loads with "ALL" selected by default
document.addEventListener('DOMContentLoaded', function() {
    updateDashboard('ALL');
});

document.addEventListener('DOMContentLoaded', function() {
    const firstCard = document.querySelector('.cards-wrapper .card:nth-child(1)');
    const fifthCard = document.querySelector('.cards-wrapper .card:nth-child(5)');
    if (firstCard) {
        firstCard.addEventListener('click', function() {
            const sspDropdown = document.getElementById('ssp-dropdown');
            const sspValue = sspDropdown ? sspDropdown.value : 'ALL'; // Get the current SSP value or default to 'ALL'
            const vstatusValue = 'Resolved'; // Static value for vstatus
            const baseUrl = `vulnerabilities.html`;
            const sspParam = sspValue !== 'ALL' ? `?ssp=${sspValue}` : '';
            const vstatusParam = `vstatus=${vstatusValue}`;
            const url = `${baseUrl}${sspParam}${sspParam ? '&' : '?'}${vstatusParam}`;
            window.location.href = url;
        });
    }
    if (fifthCard) {
        fifthCard.addEventListener('click', function() {
            const sspDropdown = document.getElementById('ssp-dropdown');
            const sspValue = sspDropdown ? sspDropdown.value : 'ALL'; // Get the current SSP value or default to 'ALL'
            const url = sspValue !== 'ALL' ? `assets.html?ssp=${sspValue}` : 'assets.html'; // Redirect to Assets.html with SSP parameter if not 'ALL'
            window.location.href = url;
        });
    }
});