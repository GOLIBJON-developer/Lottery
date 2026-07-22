Qanday ishlatiladi (Install / Upgrade)?
Ushbu Helm chart tayyor bo'lgandan so'ng, klasterga o'rnatish yoki yangilash uchun har safar o'zingiz boshida yozganingizdek oddiygina buyruq ishlatasiz:Bash
Aynan shu papka ichida turganingizda, Helm chart'ni o'rnatish va uni brauzerda ko'rish bosqichlari:

1-qadam: Helm Chart'ni klasterga o'rnatish (Deploy)
Hozir chart papkasining ichida (/helmfiles) bo'lganingiz uchun oxiriga . (joriy papka) qo'yib buyruqni yurgizasiz:Bash

```
helm upgrade --install raffle-ui . -n default
```

2-qadam: Podlar va Servis ishga tushganini tekshirish
Deploy bo'lgach, podlar tayyor holatga kelganini ko'rib olasiz:Bash

```
kubectl get pods,svc,ingress
```

Eslatma: Podlar statusi 1/1 Running bo'lishini bir necha soniya kuting.

3-qadam: Brauzerda ko'rish (2 xil yo'li bor)
🚀 A-yo'l: Eng tez va oson yo'l (Port-Forward)
Hech qanday DNS yoki Ingress sozlab o'tirmasdan, K8s servisining 80-portini kompyuteringizning 8080 portiga bog'lab olasiz:Bash

```
kubectl port-forward service/raffle-ui-service 8080:80
# Agar ArgoCD 'raffle' namespace'iga deploy qilgan bo'lsa:
kubectl port-forward service/raffle-ui-service 8081:80 -n raffle
```

Endi laptopingiz brauzerida yangi tab ochib kiring:
👉 http://localhost:8080

Agar kelgusida image tagini o'zgartirmoqchi bo'lsangiz (1.0.1 ga), to'g'ridan-to'g'ri buyruq orqali values'ni override qilib yuborishingiz mumkin:Bash

```
helm upgrade --install raffle-ui ./raffle-ui-chart --set image.tag=1.0.1
```
------------------------------------------------------------------------

Barcha yaratilgan resurslarni (Helm release, podlar, servislar va ingress) klasteringizdan to'liq va toza o'chirish uchun quyidagi buyruqlarni ketma-ket bajaring:

---

### 1. Helm orqali o'rnatilgan release'ni o'chirish

Ushbu buyruq Helm chart orqali yaratilgan barcha pod, service va ingress'larni bir martada o'chirib tashlaydi:

```bash
helm uninstall raffle-ui -n default

```

---

### 2. Har ehtimolga qarshi qolgan resurslarni tekshirish

Helm'dan tashqari ilgari `kubectl apply` bilan yaratilgan eski resurslar qolib ketmaganini tekshiramiz:

```bash
kubectl get pods,svc,ingress -l app=raffle-ui

```

Agar hali ham biror narsa ko'rinib turgan bo'lsa, ularni qo'lda tozalash buyrug'i:

```bash
kubectl delete deployment raffle-ui-deployment
kubectl delete service raffle-ui-service
kubectl delete ingress raffle-ui-ingress

```

---

### 3. (Ixtiyoriy) Minikube klasterini ham to'liq o'chirib tashlash

Aga siz Minikube klasteringizni to'liq nolga keltirmoqchi va xotirani bo'shatmoqchi bo'lsangiz:

```bash
# Klasterni to'xtatish
minikube stop

# Klasterni butunlay o'chirib tashlash
minikube delete

```

> **Eslatma:** `/etc/hosts` faylingizga qo'shgan `raffle.yourdomain.com` qatorini ham tahrirlab olib tashlashingiz mumkin.
