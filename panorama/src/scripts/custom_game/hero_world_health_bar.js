(function () {
    "use strict";

    var TABLE = "survival_hero_health_bar";
    var PREFIX = "unit_";
    var panels = {};
    var states = {};
    var container = $("#SurvivalHeroWorldHealthBars");


    function localTeam() {
        try {
            return Number(Players.GetTeam(Game.GetLocalPlayerID()));
        } catch (error) {
            return -1;
        }
    }

    function windowPosition(panel) {
        if (!panel || !panel.GetPositionWithinWindow) return { x: 0, y: 0 };
        var position = panel.GetPositionWithinWindow();
        return {
            x: Number(position && position.x) || 0,
            y: Number(position && position.y) || 0
        };
    }

    function validPanel(target) {
        return target && (!target.IsValid || target.IsValid());
    }

    function ensurePanel(key) {
        if (validPanel(panels[key])) return panels[key];
        if (!container) return null;
        var bar = $.CreatePanel("Panel", container, "SurvivalHeroWorldHealth_" + key);
        bar.style.visibility = "collapse";
        bar.AddClass("SurvivalHeroWorldHealthBar");
        bar.hittest = false;
        var fill = $.CreatePanel("Panel", bar, "");
        fill.AddClass("SurvivalHeroWorldHealthFill");
        fill.hittest = false;
        for (var index = 1; index < 10; index++) {
            var divider = $.CreatePanel("Panel", bar, "");
            divider.AddClass("SurvivalHeroWorldHealthTick");
            divider.AddClass("SurvivalHeroWorldHealthTick" + (index * 10));
            divider.hittest = false;
        }
        bar.__fill = fill;
        panels[key] = bar;
        return bar;
    }

    function hide(key) {
        var bar = panels[key];
        if (validPanel(bar)) bar.style.visibility = "collapse";
    }

    function removePanel(key) {
        var bar = panels[key];
        if (validPanel(bar)) bar.DeleteAsync(0.0);
        delete panels[key];
    }

    function predictedLoss(forecasts, now) {
        var loss = 0;
        for (var i = 0; i < forecasts.length; i++) {
            var f = forecasts[i];
            loss += f.fraction * Math.max(0, Math.min(1, (now - f.start) / (f.due - f.start)));
        }
        return loss;
    }

    function setForecast(bar, value, health, maximum) {
        bar.__healthFraction = Math.min(1, health / maximum);
        bar.__forecasts = [];
        var input = value.laser_forecast || {};
        Object.keys(input).forEach(function (key) {
            var f = input[key] || {};
            var start = Number(f.start), due = Number(f.due), fraction = Number(f.fraction);
            if (isFinite(start) && isFinite(due) && due > start && isFinite(fraction) && fraction > 0) {
                bar.__forecasts.push({start:start, due:due, fraction:fraction});
            }
        });
        bar.__forecasts.sort(function (a,b) { return a.due - b.due; });
        // Cap the last predicted hit across its full remaining interval, so an
        // overkill hit empties the bar at settlement, never partway through it.
        var cumulative = 0;
        bar.__forecastScale = 1;
        for (var i = 0; i < bar.__forecasts.length; i++) {
            cumulative += bar.__forecasts[i].fraction;
            if (cumulative >= bar.__healthFraction) {
                bar.__forecastScale = bar.__healthFraction /
                    Math.max(0.000001, predictedLoss(bar.__forecasts, bar.__forecasts[i].due));
                break;
            }
        }
    }

    function renderHealth(bar, value) {
        var fraction = bar.__healthFraction;
        var forecasts = bar.__forecasts || [];
        var now = Game.GetGameTime ? Number(Game.GetGameTime()) : NaN;
        if (forecasts.length && isFinite(now)) {
            // Game time freezes during pause. Never extrapolate a missed tick
            // indefinitely; server corrections/stop notices reset the baseline.
            if (now <= forecasts[0].due + 0.15) {
                fraction -= predictedLoss(forecasts, now) * bar.__forecastScale;
            }
        }
        if (Number(value.alive) !== 1) fraction = 0;
        var width = (Math.max(0, Math.min(1, fraction)) * 100).toFixed(3) + "%";
        if (width !== bar.__width) {
            bar.__fill.style.width = width;
            bar.__width = width;
        }
    }

    function applyState(key, value) {
        if (!value || Number(value.removed) === 1) {
            delete states[key];
            removePanel(key);
            return;
        }
        states[key] = value;
        var bar = ensurePanel(key);
        if (!bar) return;
        var health = Math.max(0, Number(value.health) || 0);
        var maximum = Math.max(1, Number(value.max_health) || 1);
        var unitTeam = Number(value.team);
        var playerTeam = localTeam();
        bar.SetHasClass(
            "SurvivalEnemyHealthBar",
            unitTeam >= 0 && playerTeam >= 0 && unitTeam !== playerTeam
        );
        // Forecast only the upcoming server hit, using the existing frame loop.
        // A trailing CSS tween would again leave visible health at lethal time.
        bar.__fill.style.transitionDuration = "0s";
        setForecast(bar, value, health, maximum);
        renderHealth(bar, value);
        if (Number(value.alive) !== 1 || health <= 0) hide(key);
    }

    function onTableChanged(tableName, key, value) {
        if (tableName === TABLE && key.indexOf(PREFIX) === 0) {
            applyState(key, value);
        }
    }

    function updatePositions() {
        if (!container) return;
        // Schedule before touching entities: a unit can disappear between an
        // IsValidEntity check and a native API call during hero replacement.
        // Such an exception must never freeze every overhead bar on screen.
        $.Schedule(0.0, updatePositions);
        var scaleX = Number(container.actualuiscale_x) || 1;
        var scaleY = Number(container.actualuiscale_y) || 1;
        var containerPosition = windowPosition(container);
        var visibility=typeof GameUI!=="undefined"?GameUI.CustomUIConfig().SurvivalWorldOverlayVisibility:null;
        var occlusion=visibility?visibility.Capture():null;
        Object.keys(states).forEach(function (key) {
            try {
            var state = states[key];
            var entindex = Number(state.entindex);
            if (!isFinite(entindex) || entindex < 0 || !Entities.IsValidEntity(entindex)) {
                removePanel(key);
                return;
            }
            var bar = ensurePanel(key);
            if (!bar || Number(state.alive) !== 1
                || (Entities.IsAlive && !Entities.IsAlive(entindex))
                || (Entities.IsDormant && Entities.IsDormant(entindex))
                || (state.unit_name && Entities.GetUnitName
                    && Entities.GetUnitName(entindex) !== state.unit_name)) {
                hide(key);
                return;
            }
            var origin = Entities.GetAbsOrigin(entindex);
            if (!origin || origin.length < 3 || Number(origin[2]) < -5000) {
                hide(key);
                return;
            }
            var height = 190;
            try {
                if (Entities.GetHealthBarOffset) {
                    var configuredHeight = Number(Entities.GetHealthBarOffset(entindex));
                    // A KV offset of -1 hides the native bar and is not a usable
                    // world height for this custom continuous health bar.
                    if (isFinite(configuredHeight) && configuredHeight > 0) {
                        height = configuredHeight;
                    }
                }
            } catch (error) {}
            var screenX = Game.WorldToScreenX(
                origin[0], origin[1], Number(origin[2]) + height
            );
            var screenY = Game.WorldToScreenY(
                origin[0], origin[1], Number(origin[2]) + height
            );
            if (!isFinite(screenX) || !isFinite(screenY)
                || screenX < 0 || screenY < 0) {
                hide(key);
                return;
            }
            var localX = (screenX - containerPosition.x) / scaleX - 31;
            var localY = (screenY - containerPosition.y) / scaleY - 26;
            if (!isFinite(localX) || !isFinite(localY)) {
                hide(key);
                return;
            }
            if(visibility&&visibility.Overlaps(occlusion,screenX-31*scaleX,screenY-26*scaleY,62*scaleX,11*scaleY)){
                hide(key);return;
            }
            if (bar.__forecasts && bar.__forecasts.length) renderHealth(bar, state);
            bar.style.position = localX.toFixed(2) + "px "
                + localY.toFixed(2) + "px 0px";
            bar.style.visibility = "visible";
            } catch (error) {
                hide(key);
            }
        });
        // Run once per Panorama frame. The previous fixed 30 Hz layout update
        // visibly lagged behind the engine's native overhead bars while units
        // or the camera were moving.
    }

    var initialValues = CustomNetTables.GetAllTableValues(TABLE) || {};
    Object.keys(initialValues).forEach(function (indexOrKey) {
        var entry = initialValues[indexOrKey];
        // Panorama versions have returned either an object map or an array of
        // { key, value } records. Support both shapes when restoring units.
        if (entry && entry.key !== undefined && entry.value !== undefined) {
            if (String(entry.key).indexOf(PREFIX) === 0) {
                applyState(String(entry.key), entry.value);
            }
            return;
        }
        if (String(indexOrKey).indexOf(PREFIX) === 0) {
            applyState(String(indexOrKey), entry);
        }
    });
    CustomNetTables.SubscribeNetTableListener(TABLE, onTableChanged);
    updatePositions();
})();
