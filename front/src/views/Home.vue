<template>
    <v-container grid-list-xl>
        <v-layout
                flex-child
                wrap
        >
            <v-flex xs6>
                <div class="hello" ref="chartdiv2">
                </div>
            </v-flex>
            <v-flex xs6>
                <div class="hello" ref="chartdiv3">
                </div>
            </v-flex>
            <v-flex xs12>
                <div class="hello" ref="chartdiv">
                </div>
            </v-flex>
        </v-layout>
    </v-container>
</template>

<script>
    import * as am4core from "@amcharts/amcharts4/core";
    import * as am4charts from "@amcharts/amcharts4/charts";
    import am4themes_dark from "@amcharts/amcharts4/themes/dark.js";

    /* Chart code */
    // Themes begin
    am4core.useTheme(am4themes_dark);
    export default {
        name: 'home',
        mounted() {
            this.chart1();
            this.chart2();
            this.chart3();
        },

        methods: {
            chart1() {
                let chart = am4core.create(this.$refs.chartdiv, am4charts.XYChart);
                chart.hiddenState.properties.opacity = 0; // this creates initial fade-in

                chart.maskBullets = false;

                let xAxis = chart.xAxes.push( new am4charts.CategoryAxis() );
                let yAxis = chart.yAxes.push( new am4charts.CategoryAxis() );

                xAxis.dataFields.category = "x";
                yAxis.dataFields.category = "y";

                xAxis.renderer.grid.template.disabled = true;
                xAxis.renderer.minGridDistance = 40;

                yAxis.renderer.grid.template.disabled = true;
                yAxis.renderer.inversed = true;
                yAxis.renderer.minGridDistance = 30;

                let series = chart.series.push( new am4charts.ColumnSeries() );
                series.dataFields.categoryX = "x";
                series.dataFields.categoryY = "y";
                series.dataFields.value = "value";
                series.sequencedInterpolation = true;
                series.defaultState.transitionDuration = 3000;

// Set up column appearance
                let column = series.columns.template;
                column.strokeWidth = 2;
                column.strokeOpacity = 1;
                column.stroke = am4core.color( "#ffffff" );
                column.tooltipText = "{x}, {y}: {value.workingValue.formatNumber('#.')}";
                column.width = am4core.percent( 100 );
                column.height = am4core.percent( 100 );
                column.column.cornerRadius(6, 6, 6, 6);
                column.propertyFields.fill = "color";

// Set up bullet appearance
                let bullet1 = series.bullets.push(new am4charts.CircleBullet());
                bullet1.circle.propertyFields.radius = "value";
                bullet1.circle.fill = am4core.color("#000");
                bullet1.circle.strokeWidth = 0;
                bullet1.circle.fillOpacity = 0.7;
                bullet1.interactionsEnabled = false;

                let bullet2 = series.bullets.push(new am4charts.LabelBullet());
                bullet2.label.text = "{value}";
                bullet2.label.fill = am4core.color("#fff");
                bullet2.zIndex = 1;
                bullet2.fontSize = 11;
                bullet2.interactionsEnabled = false;

// define colors
                let colors = {
                    "critical": chart.colors.getIndex(0).brighten(-0.8),
                    "bad": chart.colors.getIndex(1).brighten(-0.6),
                    "medium": chart.colors.getIndex(1).brighten(-0.4),
                    "good": chart.colors.getIndex(1).brighten(-0.2),
                    "verygood": chart.colors.getIndex(1).brighten(0)
                };

                chart.data = [ {
                    "y": "Critical",
                    "x": "Very good",
                    "color": colors.medium,
                    "value": 20
                }, {
                    "y": "Bad",
                    "x": "Very good",
                    "color": colors.good,
                    "value": 15
                }, {
                    "y": "Medium",
                    "x": "Very good",
                    "color": colors.verygood,
                    "value": 25
                }, {
                    "y": "Good",
                    "x": "Very good",
                    "color": colors.verygood,
                    "value": 15
                }, {
                    "y": "Very good",
                    "x": "Very good",
                    "color": colors.verygood,
                    "value": 12
                },

                    {
                        "y": "Critical",
                        "x": "Good",
                        "color": colors.bad,
                        "value": 30
                    }, {
                        "y": "Bad",
                        "x": "Good",
                        "color": colors.medium,
                        "value": 24
                    }, {
                        "y": "Medium",
                        "x": "Good",
                        "color": colors.good,
                        "value": 25
                    }, {
                        "y": "Good",
                        "x": "Good",
                        "color": colors.verygood,
                        "value": 15
                    }, {
                        "y": "Very good",
                        "x": "Good",
                        "color": colors.verygood,
                        "value": 25
                    },

                    {
                        "y": "Critical",
                        "x": "Medium",
                        "color": colors.bad,
                        "value": 33
                    }, {
                        "y": "Bad",
                        "x": "Medium",
                        "color": colors.bad,
                        "value": 14
                    }, {
                        "y": "Medium",
                        "x": "Medium",
                        "color": colors.medium,
                        "value": 20
                    }, {
                        "y": "Good",
                        "x": "Medium",
                        "color": colors.good,
                        "value": 19
                    }, {
                        "y": "Very good",
                        "x": "Medium",
                        "color": colors.good,
                        "value": 25
                    },

                    {
                        "y": "Critical",
                        "x": "Bad",
                        "color": colors.critical,
                        "value": 31
                    }, {
                        "y": "Bad",
                        "x": "Bad",
                        "color": colors.critical,
                        "value": 24
                    }, {
                        "y": "Medium",
                        "x": "Bad",
                        "color": colors.bad,
                        "value": 25
                    }, {
                        "y": "Good",
                        "x": "Bad",
                        "color": colors.medium,
                        "value": 15
                    }, {
                        "y": "Very good",
                        "x": "Bad",
                        "color": colors.good,
                        "value": 15
                    },

                    {
                        "y": "Critical",
                        "x": "Critical",
                        "color": colors.critical,
                        "value": 12
                    }, {
                        "y": "Bad",
                        "x": "Critical",
                        "color": colors.critical,
                        "value": 14
                    }, {
                        "y": "Medium",
                        "x": "Critical",
                        "color": colors.critical,
                        "value": 15
                    }, {
                        "y": "Good",
                        "x": "Critical",
                        "color": colors.bad,
                        "value": 25
                    }, {
                        "y": "Very good",
                        "x": "Critical",
                        "color": colors.medium,
                        "value": 19
                    }
                ];

                this.chart1 = chart;
            },

            chart2() {
                let chart = am4core.create(this.$refs.chartdiv2, am4charts.PieChart);
                chart.hiddenState.properties.opacity = 0; // this creates initial fade-in

                chart.data = [
                    {
                        country: "Lithuania",
                        value: 260
                    },
                    {
                        country: "Czech Republic",
                        value: 230
                    },
                    {
                        country: "Ireland",
                        value: 200
                    },
                    {
                        country: "Germany",
                        value: 165
                    },
                    {
                        country: "Australia",
                        value: 139
                    },
                    {
                        country: "Austria",
                        value: 128
                    }
                ];

                var series = chart.series.push(new am4charts.PieSeries());
                series.dataFields.value = "value";
                series.dataFields.radiusValue = "value";
                series.dataFields.category = "country";
                series.slices.template.cornerRadius = 6;
                series.colors.step = 3;

                series.hiddenState.properties.endAngle = -90;

                chart.legend = new am4charts.Legend();
                this.chart2 = chart;
            },

            chart3() {
                let chart = am4core.create(this.$refs.chartdiv3, am4charts.XYChart);

// Add data
                chart.data = [ {
                    "year": "2003",
                    "europe": 2.5,
                    "namerica": 2.5,
                    "asia": 2.1,
                    "lamerica": 1.2,
                    "meast": 0.2,
                    "africa": 0.1
                }, {
                    "year": "2004",
                    "europe": 2.6,
                    "namerica": 2.7,
                    "asia": 2.2,
                    "lamerica": 1.3,
                    "meast": 0.3,
                    "africa": 0.1
                }, {
                    "year": "2005",
                    "europe": 2.8,
                    "namerica": 2.9,
                    "asia": 2.4,
                    "lamerica": 1.4,
                    "meast": 0.3,
                    "africa": 0.1
                } ];

// Create axes
                var categoryAxis = chart.xAxes.push(new am4charts.CategoryAxis());
                categoryAxis.dataFields.category = "year";
                categoryAxis.title.text = "Local country offices";
                categoryAxis.renderer.grid.template.location = 0;
                categoryAxis.renderer.minGridDistance = 20;
                categoryAxis.renderer.cellStartLocation = 0.1;
                categoryAxis.renderer.cellEndLocation = 0.9;

                var  valueAxis = chart.yAxes.push(new am4charts.ValueAxis());
                valueAxis.min = 0;
                valueAxis.title.text = "Expenditure (M)";

// Create series
                function createSeries(field, name, stacked) {
                    var series = chart.series.push(new am4charts.ColumnSeries());
                    series.dataFields.valueY = field;
                    series.dataFields.categoryX = "year";
                    series.name = name;
                    series.columns.template.tooltipText = "{name}: [bold]{valueY}[/]";
                    series.stacked = stacked;
                    series.columns.template.width = am4core.percent(95);
                }

                createSeries("europe", "Europe", false);
                createSeries("namerica", "North America", true);
                createSeries("asia", "Asia", false);
                createSeries("lamerica", "Latin America", true);
                createSeries("meast", "Middle East", true);
                createSeries("africa", "Africa", true);

// Add legend
                chart.legend = new am4charts.Legend();
                this.chart3 = chart;
            }
        },
        beforeDestroy() {
            if (this.chart1) {
                this.chart1.dispose();
            }
            if (this.chart2) {
                this.chart2.dispose();
            }
            if (this.chart3) {
                this.chart3.dispose();
            }
        }
    }
</script>

<style scoped>
    .hello {
        width: 100%;
        min-height: 400px;
    }
</style>