(function () {
    "use strict";
    var catalog = window.SurvivalPublicShop;
    var id = function (name) { return document.getElementById(name); };
    var names = {CNY: "人民币", u_coin: "G币", shop_points: "商城积分", shop_gold: "商城金币"};
    var selected = null;
    function text(value) { return String(value).replace(/U币/g, "G币"); }
    function price(item) { return item.currency === "CNY" ? "¥" + (item.price / 100).toFixed(2) : item.price + " " + names[item.currency]; }
    function node(type, content, className) {
        var item = document.createElement(type);
        if (content !== undefined) item.textContent = text(content);
        if (className) item.className = className;
        return item;
    }
    function detail(item) {
        selected = item.offer_id;
        id("title").textContent = text(item.title);
        id("price").textContent = price(item);
        id("description").textContent = text(item.description);
        id("limit").textContent = (item.purchase_limit ? "配置限购 " + item.purchase_limit + " 次" : "配置未设次数限购") + (item.required_vip_level ? " · 需要 VIP " + item.required_vip_level : "") + "；实际资格须登录后由服务端核验。";
        id("rewards").replaceChildren();
        item.reward_lines.forEach(function (line) {
            id("rewards").appendChild(node("li", line.label + " ×" + line.quantity + (line.duration_days ? "（" + line.duration_days + "天）" : "")));
        });
        Array.prototype.forEach.call(id("products").children, function (button) { button.setAttribute("aria-pressed", button.dataset.offer === selected ? "true" : "false"); });
    }
    function render() {
        var query = id("search").value.trim().toLocaleLowerCase(), category = id("category").value, currency = id("currency").value;
        var items = catalog.products.filter(function (item) {
            return (category === "all" || item.category_id === category) && (currency === "all" || item.currency === currency) && (!query || text(item.title + " " + item.description + " " + item.reward_lines.map(function (line) { return line.label; }).join(" ")).toLocaleLowerCase().indexOf(query) >= 0);
        });
        id("products").replaceChildren();
        items.forEach(function (item) {
            var button = node("button"), name = node("span", item.title, "product-name");
            button.type = "button"; button.dataset.offer = item.offer_id;
            name.appendChild(node("span", item.currency === "CNY" ? "人民币报价" : "游戏货币兑换报价", "offer-kind"));
            button.appendChild(name); button.appendChild(node("span", price(item), "product-price"));
            button.setAttribute("aria-pressed", item.offer_id === selected ? "true" : "false");
            button.addEventListener("click", function () { detail(item); });
            id("products").appendChild(button);
        });
        id("status").textContent = "显示 " + items.length + " 项报价 / 全部 " + catalog.products.length + " 项；同一商品的不同币种报价分别展示。";
        if (items.length && !items.some(function (item) { return item.offer_id === selected; })) detail(items[0]);
        if (!items.length) {
            selected = null;
            id("title").textContent = "没有符合筛选的商品";
            ["price", "description", "limit"].forEach(function (name) { id(name).textContent = ""; });
            id("rewards").replaceChildren();
        }
    }
    if (!catalog || catalog.schema_version !== 1 || catalog.checkout_enabled !== false || !Array.isArray(catalog.products)) {
        id("status").textContent = "目录暂不可用，请稍后刷新。支付保持关闭。";
        return;
    }
    catalog.categories.forEach(function (category) {
        var option = node("option", category.label); option.value = category.id; id("category").appendChild(option);
    });
    id("revision").textContent = catalog.catalog_sha256.slice(0, 16);
    ["category", "currency"].forEach(function (name) { id(name).addEventListener("change", render); });
    id("search").addEventListener("input", render);
    render();
})();
