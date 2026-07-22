
# useful commands 
# 1. Manifestni klasterga tatbiq etish
```
kubectl apply -f raffle-ui-k8s.yaml
```
# 2. Podlar va Servis ishga tushganini ko'rish
```
kubectl get pods,svc,ingress -l app=raffle-ui
```
# 3. Loglarni jonli kuzatish
```
kubectl logs -l app=raffle-ui -f

kubectl get pods -l app=raffle-ui

kubectl rollout restart deployment raffle-ui-deployment

kubectl get pods -w
```
Nega SSH tunnel va localhost:3000 ishlamadi?
Sababi juda sodda: Kubernetes klasteri izolyatsiyalangan tarmoqda ishlaydi.
Siz yarataotgan Service turi ClusterIP bo'lgani uchun u portni Ubuntu serveringizning 
o'ziga (127.0.0.1) chiqarmaydi. Natijada siz Ubuntu serverda 127.0.0.1:3000 ga SSH tunnel qilganingizda, 
Ubuntu serverining o'zida 3000-portda hech narsa tinglamayotgan (listen qilmayotgan) edi.

1-qadam: Ubuntu Server terminalida kran ochamiz
Ubuntu serveringizda quyidagi buyruqni yurgizasiz:
```
kubectl port-forward --address 0.0.0.0 svc/raffle-ui-service 3000:80
```
(Eslatma: Terminalni shunday ochiq qoldiring, yopmang).

2-qadam: Laptopingizdan ulanish
Boya SSH orqali qilgan port-forwardingiz endi ishlaydi! Laptopingizdagi GitBash terminalida: Bash
```
ssh -L 3000:127.0.0.1:3000 golib@UBUNTU_IP
```
Endi laptopingiz brauzerini ochib, http://localhost:3000 ga kirsangiz, Next.js loyihangiz namoyon bo'ladi!

-------------------------------------------------------------------------------------------------------------

2-YO'L: Minikube Ingress orqali (Haqiqiy domen bilan kirish)
Siz raffle-ui-k8s.yaml faylingizga Ingress yozgansiz (raffle.yourdomain.com). Minikube'da Ingress ishlashi uchun 2 ta kichik buyruq kerak:

1-qadam: Minikube Ingress addon'ini yoqamiz
Ubuntu serverda:Bash
```
minikube addons enable ingress
```
2-qadam: Minikube Tunnel'ni ishga tushiramiz
Minikube alohida VM/Docker ichida bo'lgani uchun, Ingress IP'sini Ubuntu serverga bog'lash uchun yangi terminal tabida quyidagi buyruqni beramiz:Bash
```
minikube tunnel
```
(Parol so'rasa Ubuntu parolingizni yozasiz va shu terminalni ham ochiq qoldirasiz).

3-qadam: Laptopingizning hosts fayliga yozish
Laptopingizdagi hosts fayliga Ubuntu serveringiz IP manzilini va domenni qo'shasiz:Plaintext
```
192.168.X.X   raffle.yourdomain.com
```
Endi laptopingiz brauzeridan [http://raffle.yourdomain.com](http://raffle.yourdomain.com) deb kirsangiz, loyihangiz Ingress orqali ochiladi!

Kubernetes klasteridan barcha yaratilgan resurslarni (Deployment, Service, Ingress va barcha Podlarni) to'liq o'chirib tashlashning 2 xil usuli bor:
Manifest fayli orqali (Eng oson va toza yo'li) 
Label (yorliq) orqali to'g'ridan-to'g'ri o'chirish
```
kubectl delete -f raffle-ui-k8s.yaml
kubectl delete deployment,service,ingress -l app=raffle-ui
kubectl get all,ingress -l app=raffle-ui
```