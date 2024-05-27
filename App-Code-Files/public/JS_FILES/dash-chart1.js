// Encapsulate Graph1
(function() {
  document.addEventListener('DOMContentLoaded', function () {
    let chartOptions = {
      container: document.getElementById('graph1'),
      autoSize: true,
      title: { text: 'Open Vulnerabilities by Product', fontSize: 18 },
      subtitle: { text: 'Based on selected SSP' },
      series: [{ type: 'bar', xKey: 'product', yKey: 'openVulnerabilities', yName: 'Open Vulnerabilities' }],
      axes: [
        { type: 'category', position: 'bottom', title: { text: 'Product' } },
        { type: 'number', position: 'left', title: { text: 'Number of Open Vulnerabilities' } }
      ],
      legend: { enabled: false },
      data: []
    };
    let myChart = null;

    const fetchDataAndRenderChart = async (sspParam) => {
      const sspDropdown = document.getElementById('ssp-dropdown');
      const ssp = sspParam || sspDropdown.value;
      const response = await fetch(`/api/vulnerabilityCountsByProduct?ssp=${ssp}`);
      const data = await response.json();
      chartOptions.data = data;
      chartOptions.subtitle = { text: `Results for: ${ssp}` };
      if (myChart) {
        agCharts.AgCharts.update(myChart, chartOptions);
      } else {
        myChart = agCharts.AgCharts.create(chartOptions);
      }
    };
    
    document.getElementById('ssp-dropdown').addEventListener('change', function(event) {
      const ssp = event.target.value;
      fetchDataAndRenderChart(ssp);
    });
    fetchDataAndRenderChart();
  });
})();

// Encapsulate Graph2
(function() {
  document.addEventListener('DOMContentLoaded', function () {
    let chartOptions = {
      container: document.getElementById('graph2'),
      autoSize: true,
      title: { text: 'Open Vulnerabilities Over Time', fontSize: 18 },
      subtitle: { text: 'Last 30 days' },
      series: [{ type: 'line', xKey: 'date', yKey: 'openVulnerabilities' }],
      axes: [
        { type: 'category', position: 'bottom', title: { text: 'Date' } },
        { type: 'number', position: 'left', title: { text: 'Number of Open Vulnerabilities' } }
      ],
      data: []
    };
    let myChart = null;

    const fetchDataAndRenderChart = async (sspParam) => {
      const sspDropdown = document.getElementById('ssp-dropdown');
      const ssp = sspParam || sspDropdown.value;
      const response = await fetch(`/api/vulnerability-snapshot?ssp=${encodeURIComponent(ssp)}`);
      let data = await response.json();
    
      let maxTotalCount = 0;
      data.forEach(entry => {
        maxTotalCount = Math.max(maxTotalCount, entry.totalVulnerabilities);
      });
    
      // Define the max value for the y-axis
      const yAxisMax = maxTotalCount + (maxTotalCount * 0.01);  // Adding a 1% buffer
    
      // Prepare the data for the chart
      const formattedData = data.map(entry => ({
        ...entry,
        date: entry.date.split('T')[0],
      }));
    
      // Setup or update the chart
      if (myChart) {
        // Update the chart if it already exists
        agCharts.AgCharts.update(myChart, {
          ...chartOptions,
          axes: [
            chartOptions.axes[0], // Keep x-axis as is
            { ...chartOptions.axes[1], max: yAxisMax }, // Update y-axis with new max
          ],
          data: formattedData,
        });
      } else {
        // Create the chart if it doesn't exist
        myChart = agCharts.AgCharts.create({
          ...chartOptions,
          axes: [
            chartOptions.axes[0], // Keep x-axis as is
            { ...chartOptions.axes[1], max: yAxisMax }, // Update y-axis with new max
          ],
          data: formattedData,
        });
      }
    };
    
    
    
    

    document.getElementById('ssp-dropdown').addEventListener('change', function(event) {
      const ssp = event.target.value;
      fetchDataAndRenderChart(ssp);
    });

    // Initial data fetch
    fetchDataAndRenderChart();
  });
})();

